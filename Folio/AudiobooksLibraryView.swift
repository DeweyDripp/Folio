import SwiftUI
import UIKit
import PhotosUI

struct AudiobooksLibraryView: View {
    @State var audiobooks: [Audiobook]
    @State private var editing: Audiobook?
    @State private var deleting: Audiobook?
    @State private var shelving: Audiobook?
    @State private var searchText = ""
    @State private var filter: AudiobookFilter = .all
    @State private var showingInsights = false

    private var shelves: [String] {
        Set(audiobooks.compactMap { AudiobookStore.shelf(for: $0.id) }).sorted()
    }

    private var visibleAudiobooks: [Audiobook] {
        audiobooks.filter { audiobook in
            let matchesSearch = searchText.isEmpty || audiobook.title.localizedCaseInsensitiveContains(searchText) || audiobook.author.localizedCaseInsensitiveContains(searchText)
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .favorites: matchesFilter = AudiobookStore.isFavorite(audiobook.id)
            case .recent: matchesFilter = AudiobookStore.lastPlayed(audiobook.id) != nil
            case .shelf(let name): matchesFilter = AudiobookStore.shelf(for: audiobook.id) == name
            }
            return matchesSearch && matchesFilter
        }
        .sorted { (AudiobookStore.lastPlayed($0.id) ?? .distantPast) > (AudiobookStore.lastPlayed($1.id) ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 24)], spacing: 28) {
                ForEach(visibleAudiobooks) { audiobook in
                    NavigationLink {
                        AudiobookPlayerView(audiobook: audiobook)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.indigo.gradient)
                                .aspectRatio(0.68, contentMode: .fit)
                                .overlay {
                                    if let data = audiobook.coverData, let image = UIImage(data: data) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(Color.black.opacity(0.08))
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                    } else {
                                        Image(systemName: "headphones.circle.fill").font(.system(size: 44)).foregroundStyle(.white)
                                    }
                                }
                            Text(audiobook.title).font(.headline).lineLimit(1)
                            Text(audiobook.author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            let progress = AudiobookStore.progress(for: audiobook)
                            HStack(spacing: 8) {
                                ProgressView(value: progress)
                                Text("\(Int((progress * 100).rounded()))%")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }.buttonStyle(.plain).contextMenu {
                        Button { editing = audiobook } label: { Label("Audiobook Info", systemImage: "info.circle") }
                        Button { AudiobookStore.setFavorite(!AudiobookStore.isFavorite(audiobook.id), for: audiobook.id) } label: {
                            Label(AudiobookStore.isFavorite(audiobook.id) ? "Remove Favorite" : "Add Favorite", systemImage: AudiobookStore.isFavorite(audiobook.id) ? "star.slash" : "star")
                        }
                        Button { shelving = audiobook } label: { Label("Assign Shelf", systemImage: "folder") }
                        Button(role: .destructive) { deleting = audiobook } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }.padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Audiobooks")
        .searchable(text: $searchText, prompt: "Search audiobooks")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingInsights = true } label: { Label("Insights", systemImage: "chart.bar.xaxis") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Filter", selection: $filter) {
                        Text("All Audiobooks").tag(AudiobookFilter.all)
                        Text("Favorites").tag(AudiobookFilter.favorites)
                        Text("Recently Played").tag(AudiobookFilter.recent)
                        ForEach(shelves, id: \.self) { shelf in Text(shelf).tag(AudiobookFilter.shelf(shelf)) }
                    }
                } label: { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") }
            }
        }
        .sheet(item: $editing) { audiobook in
            AudiobookMetadataEditor(audiobook: audiobook) { updated in
                if let index = audiobooks.firstIndex(where: { $0.id == updated.id }) { audiobooks[index] = updated; try? AudiobookStore.save(audiobooks) }
            }
        }
        .confirmationDialog("Delete Audiobook?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let audiobook = deleting, let index = audiobooks.firstIndex(where: { $0.id == audiobook.id }) {
                    audiobooks.remove(at: index); try? AudiobookStore.save(audiobooks); AudiobookStore.removeFiles(for: audiobook)
                }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        }
        .sheet(item: $shelving) { audiobook in
            AudiobookShelfEditor(currentShelf: AudiobookStore.shelf(for: audiobook.id)) { shelf in
                AudiobookStore.setShelf(shelf, for: audiobook.id)
                shelving = nil
            }
        }
        .sheet(isPresented: $showingInsights) { NavigationStack { AudiobookInsightsView(audiobooks: audiobooks) } }
    }
}

private enum AudiobookFilter: Hashable {
    case all, favorites, recent, shelf(String)
}

private struct AudiobookShelfEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var shelf: String
    let save: (String?) -> Void

    init(currentShelf: String?, save: @escaping (String?) -> Void) {
        _shelf = State(initialValue: currentShelf ?? "")
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Shelf name", text: $shelf)
                Button("Remove from Shelf", role: .destructive) { save(nil); dismiss() }
            }
            .navigationTitle("Audiobook Shelf")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(shelf); dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct AudiobookInsightsView: View {
    let audiobooks: [Audiobook]

    private var totalDuration: TimeInterval {
        audiobooks.flatMap(\.chapters).reduce(0) { $0 + ($1.duration ?? 0) }
    }

    private var listenedDuration: TimeInterval {
        audiobooks.reduce(0) { total, audiobook in
            total + audiobook.chapters.enumerated().reduce(0) { chapterTotal, item in
                let saved = UserDefaults.standard.double(forKey: AudiobookStore.positionKey(for: audiobook.id, chapter: item.offset))
                return chapterTotal + min(saved, item.element.duration ?? saved)
            }
        }
    }

    private var completedChapters: Int {
        audiobooks.reduce(0) { total, audiobook in
            total + audiobook.chapters.enumerated().filter { index, chapter in
                guard let duration = chapter.duration, duration > 0 else { return false }
                return UserDefaults.standard.double(forKey: AudiobookStore.positionKey(for: audiobook.id, chapter: index)) >= duration * 0.98
            }.count
        }
    }

    private var finishedBooks: Int {
        audiobooks.filter { AudiobookStore.progress(for: $0) >= 0.98 }.count
    }

    var body: some View {
        List {
            Section("Listening") {
                statistic("Listening time", value: format(listenedDuration), icon: "headphones")
                statistic("Library duration", value: format(totalDuration), icon: "clock")
                statistic("Chapters completed", value: "\(completedChapters)", icon: "checkmark.circle")
                statistic("Audiobooks finished", value: "\(finishedBooks)", icon: "books.vertical")
            }
            Section("Overall progress") {
                ProgressView(value: totalDuration > 0 ? listenedDuration / totalDuration : 0)
                Text("\(Int(((totalDuration > 0 ? listenedDuration / totalDuration : 0) * 100).rounded()))% listened")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Audiobook Insights")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statistic(_ title: String, value: String, icon: String) -> some View {
        LabeledContent { Text(value).monospacedDigit() } label: { Label(title, systemImage: icon) }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

private struct AudiobookMetadataEditor: View {
    let audiobook: Audiobook; let save: (Audiobook) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var author: String
    @State private var coverData: Data?
    @State private var chapterTitles: [String]
    @State private var photo: PhotosPickerItem?

    init(audiobook: Audiobook, save: @escaping (Audiobook) -> Void) {
        self.audiobook = audiobook
        self.save = save
        _title = State(initialValue: audiobook.title)
        _author = State(initialValue: audiobook.author)
        _coverData = State(initialValue: audiobook.coverData)
        _chapterTitles = State(initialValue: audiobook.chapters.map(\.title))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cover") {
                    if let coverData, let image = UIImage(data: coverData) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Choose Cover from Photos", systemImage: "photo")
                    }
                }
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                }
                Section("Chapters") {
                    ForEach(chapterTitles.indices, id: \.self) { index in
                        TextField("Chapter \(index + 1)", text: $chapterTitles[index])
                    }
                }
            }
            .navigationTitle("Audiobook Info")
            .task(id: photo) {
                if let photo { coverData = try? await photo.loadTransferable(type: Data.self) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let chapters = audiobook.chapters.enumerated().map { index, chapter in
                            AudiobookChapter(id: chapter.id, title: chapterTitles[index], fileName: chapter.fileName, duration: chapter.duration, fingerprint: chapter.fingerprint)
                        }
                        save(Audiobook(id: audiobook.id, title: title, author: author, chapters: chapters, importedAt: audiobook.importedAt, coverData: coverData))
                        dismiss()
                    }
                }
            }
        }
    }
}
