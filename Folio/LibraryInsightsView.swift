import SwiftUI

struct LibraryInsightsView: View {
    let books: [Book]

    @State private var selectedTab: InsightsTab = .notes

    var body: some View {
        VStack(spacing: 0) {
            Picker("Insights", selection: $selectedTab) {
                ForEach(InsightsTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Group {
                switch selectedTab {
                case .notes:
                    LibraryNotesList(books: books)
                case .stats:
                    ReadingStatisticsView(books: books)
                }
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum InsightsTab: String, CaseIterable, Identifiable {
    case notes
    case stats

    var id: Self { self }

    var title: String {
        switch self {
        case .notes: "Notes"
        case .stats: "Statistics"
        }
    }
}

private struct LibraryNotesList: View {
    let books: [Book]
    @State private var notes: [LibraryNote] = []

    var body: some View {
        Group {
            if notes.isEmpty {
                ContentUnavailableView(
                    "No Notes Yet",
                    systemImage: "note.text",
                    description: Text("Highlights and notes from your books will appear here.")
                )
            } else {
                List(notes) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(note.bookTitle)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(note.createdAt, format: .dateTime.month().day().year())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(note.text)
                            .font(.body)
                            .lineLimit(4)

                        if !note.note.isEmpty {
                            Label(note.note, systemImage: "note.text")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                }
                .listStyle(.insetGrouped)
            }
        }
        .task {
            loadNotes()
        }
    }

    private func loadNotes() {
        notes = books.flatMap { book in
            ReaderHighlightStore(bookID: book.id).highlights.map { highlight in
                LibraryNote(
                    id: highlight.id,
                    bookTitle: book.title,
                    text: highlight.text,
                    note: highlight.note,
                    createdAt: highlight.createdAt,
                    progression: highlight.progression ?? 0
                )
            }
        }
        .sorted {
            if $0.bookTitle == $1.bookTitle {
                return $0.progression < $1.progression
            }
            return $0.bookTitle.localizedCaseInsensitiveCompare($1.bookTitle) == .orderedAscending
        }
    }
}

private struct LibraryNote: Identifiable {
    let id: UUID
    let bookTitle: String
    let text: String
    let note: String
    let createdAt: Date
    let progression: Double
}

private struct ReadingStatisticsView: View {
    let books: [Book]
    @ObservedObject private var progressStore = ReadingProgressStore.shared

    private var startedBooks: [Book] {
        books.filter { (progressStore.progress(for: $0.id)?.fraction ?? 0) > 0 }
    }

    private var finishedCount: Int {
        startedBooks.filter { (progressStore.progress(for: $0.id)?.fraction ?? 0) >= 0.995 }.count
    }

    private var averageProgress: Double {
        guard !startedBooks.isEmpty else { return 0 }
        let total = startedBooks.reduce(0.0) { total, book in
            total + (progressStore.progress(for: book.id)?.fraction ?? 0)
        }
        return total / Double(startedBooks.count)
    }

    private var pagesRead: Int {
        books.reduce(0) { total, book in
            guard book.bookFormat != .epub,
                  let progress = progressStore.progress(for: book.id)
            else { return total }
            return total + Int((progress.fraction * Double(book.pages.count)).rounded())
        }
    }

    var body: some View {
        List {
            Section("Library") {
                statistic("Books started", value: "\(startedBooks.count)", icon: "play.circle")
                statistic("Books finished", value: "\(finishedCount)", icon: "checkmark.circle")
                statistic("Average progress", value: "\(Int((averageProgress * 100).rounded()))%", icon: "chart.bar")
                statistic("Pages read", value: "\(pagesRead)", icon: "book.pages")
            }

            if !startedBooks.isEmpty {
                Section("Continue Reading") {
                    ForEach(startedBooks.sorted { progress(for: $0) > progress(for: $1) }) { book in
                        HStack(spacing: 12) {
                            Image(systemName: book.coverSymbol)
                                .frame(width: 28)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(book.title)
                                    .lineLimit(1)
                                ProgressView(value: progress(for: book))
                            }
                            Text("\(Int((progress(for: book) * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func progress(for book: Book) -> Double {
        progressStore.progress(for: book.id)?.fraction ?? 0
    }

    private func statistic(_ title: String, value: String, icon: String) -> some View {
        LabeledContent {
            Text(value).monospacedDigit()
        } label: {
            Label(title, systemImage: icon)
        }
    }
}
