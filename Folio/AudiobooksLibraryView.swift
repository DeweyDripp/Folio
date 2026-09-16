import SwiftUI
import UIKit
import PhotosUI

struct AudiobooksLibraryView: View {
    @State var audiobooks: [Audiobook]
    @State private var editing: Audiobook?
    @State private var deleting: Audiobook?
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 24)], spacing: 28) {
                ForEach(audiobooks) { audiobook in
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
                        Button(role: .destructive) { deleting = audiobook } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }.padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Audiobooks")
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
