import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject private var readingProgress = ReadingProgressStore.shared
    @State private var importedBooks: [Book] = []
    @State private var isLoadingLibrary = true
    @State private var isShowingImporter = false
    @State private var isImporting = false
    @State private var presentedError: LibraryError?
    @State private var bookToEdit: Book?
    @State private var bookToDelete: Book?
    @State private var searchText = ""
    @State private var selectedShelf = "__all_shelves__"
    @AppStorage("library-sort") private var sortRawValue = LibrarySortOption.recent.rawValue

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 24)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if isLoadingLibrary {
                    ProgressView("Loading library…")
                } else if importedBooks.isEmpty {
                    ContentUnavailableView {
                        Label("Your Library Is Empty", systemImage: "books.vertical")
                    } description: {
                        Text("Tap the plus button to import an EPUB, PDF, or text file.")
                    }
                } else if visibleBooks.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 28) {
                            ForEach(visibleBooks) { book in
                                NavigationLink {
                                    ReaderView(book: book)
                                } label: {
                                    BookCoverView(
                                        book: book,
                                        progress: readingProgress.progress(for: book.id)
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        bookToEdit = book
                                    } label: {
                                        Label("Book Info", systemImage: "info.circle")
                                    }

                                    Button(role: .destructive) {
                                        bookToDelete = book
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        AppSettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Picker("Sort By", selection: sortSelection) {
                            ForEach(LibrarySortOption.allCases) { option in
                                Label(option.title, systemImage: option.systemImage)
                                    .tag(option)
                            }
                        }

                        if !shelves.isEmpty {
                            Divider()
                            Picker("Shelf", selection: $selectedShelf) {
                                Text("All Shelves").tag(Self.allShelves)
                                Text("Unfiled").tag(Self.unfiledShelf)
                                ForEach(shelves, id: \.self) { shelf in
                                    Text(shelf).tag(shelf)
                                }
                            }
                        }
                    } label: {
                        Label("Organize Library", systemImage: "arrow.up.arrow.down.circle")
                    }

                    Button {
                        isShowingImporter = true
                    } label: {
                        Label("Import Book", systemImage: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $isShowingImporter,
                allowedContentTypes: [.plainText, .pdf, .epub]
            ) { result in
                Task {
                    await importBook(from: result)
                }
            }
            .searchable(text: $searchText, prompt: "Search titles and authors")
            .sheet(item: $bookToEdit) { book in
                BookMetadataEditor(book: book) { updatedBook in
                    updateBook(updatedBook)
                }
            }
            .confirmationDialog(
                "Remove Book?",
                isPresented: isShowingDeleteConfirmation,
                titleVisibility: .visible,
                presenting: bookToDelete
            ) { book in
                Button("Delete \(book.title)", role: .destructive) {
                    deleteBook(book)
                }
                Button("Cancel", role: .cancel) { }
            } message: { book in
                Text("This removes \(book.title) and its reading progress from Folio. Your original imported file is not affected.")
            }
            .overlay {
                if isImporting {
                    ProgressView("Importing book…")
                        .padding(22)
                        .folioControlPanel(cornerRadius: 16)
                }
            }
            .alert(item: $presentedError) { error in
                Alert(
                    title: Text(error.title),
                    message: Text(error.message),
                    dismissButton: .cancel(Text("OK"))
                )
            }
            .task {
                loadLibrary()
                if let message = readingProgress.errorMessage {
                    presentedError = LibraryError(title: "Couldn’t Load Progress", message: message)
                    readingProgress.clearError()
                }
            }
            .onChange(of: readingProgress.errorMessage) { _, message in
                guard let message else { return }
                presentedError = LibraryError(title: "Couldn’t Save Progress", message: message)
                readingProgress.clearError()
            }
        }
    }

    private static let allShelves = "__all_shelves__"
    private static let unfiledShelf = "__unfiled_shelf__"

    private var sortSelection: Binding<LibrarySortOption> {
        Binding(
            get: { LibrarySortOption(rawValue: sortRawValue) ?? .recent },
            set: { sortRawValue = $0.rawValue }
        )
    }

    private var shelves: [String] {
        Set(importedBooks.compactMap(\.normalizedShelf)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var visibleBooks: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = importedBooks.filter { book in
            let matchesSearch = query.isEmpty
                || book.title.localizedCaseInsensitiveContains(query)
                || book.author.localizedCaseInsensitiveContains(query)
            let matchesShelf = selectedShelf == Self.allShelves
                || (selectedShelf == Self.unfiledShelf && book.normalizedShelf == nil)
                || book.normalizedShelf == selectedShelf
            return matchesSearch && matchesShelf
        }

        return sortSelection.wrappedValue.sort(filtered) { bookID in
            readingProgress.progress(for: bookID)?.updatedAt
        }
    }

    private var isShowingDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { bookToDelete != nil },
            set: { if !$0 { bookToDelete = nil } }
        )
    }

    private func updateBook(_ updatedBook: Book) {
        guard let index = importedBooks.firstIndex(where: { $0.id == updatedBook.id }) else {
            return
        }

        var updatedBooks = importedBooks
        updatedBooks[index] = updatedBook
        do {
            try ImportedBookStore.save(updatedBooks)
            importedBooks = updatedBooks
        } catch {
            showStorageError()
        }
    }

    private func deleteBook(_ book: Book) {
        let remainingBooks = importedBooks.filter { $0.id != book.id }
        do {
            try ImportedBookStore.save(remainingBooks)
            importedBooks = remainingBooks
            ReaderBookmarkStore.removeAll(for: book.id)
            ReaderHighlightStore.removeAll(for: book.id)
            readingProgress.remove(for: book.id)
            EPUBProgressStore.removeLegacyProgress(for: book.id)
            bookToDelete = nil

            do {
                try ImportedBookStore.removeImportedFiles(for: book)
            } catch {
                presentedError = LibraryError(
                    title: "Book Removed",
                    message: "The book was removed from your library, but Folio couldn’t finish cleaning up its stored file."
                )
            }
        } catch {
            showStorageError()
        }
    }

    @MainActor
    private func importBook(from result: Result<URL, Error>) async {
        isImporting = true
        defer { isImporting = false }

        do {
            let url = try result.get()
            let fingerprint = try ImportedBookLoader.fingerprint(for: url)
            guard !importedBooks.contains(where: { $0.fingerprint == fingerprint }) else {
                throw DuplicateBookError()
            }

            let book = try await ImportedBookLoader.load(from: url, fingerprint: fingerprint)
            var updatedBooks = importedBooks
            updatedBooks.insert(book, at: 0)
            do {
                try ImportedBookStore.save(updatedBooks)
                importedBooks = updatedBooks
            } catch {
                try? ImportedBookStore.removeImportedFiles(for: book)
                throw error
            }
        } catch {
            presentedError = LibraryError(title: "Couldn’t Import Book", message: error.localizedDescription)
        }
    }

    private func loadLibrary() {
        defer { isLoadingLibrary = false }
        do {
            importedBooks = try ImportedBookStore.load()
        } catch {
            presentedError = LibraryError(
                title: "Couldn’t Load Library",
                message: "Folio couldn’t read its library information. Your imported book files have not been deleted."
            )
        }
    }

    private func showStorageError() {
        presentedError = LibraryError(
            title: "Couldn’t Save Library",
            message: "Folio couldn’t save that change. Check that your device has available storage, then try again."
        )
    }
}

private struct LibraryError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct DuplicateBookError: LocalizedError {
    var errorDescription: String? {
        "That exact book is already in your Folio library."
    }
}

private extension UTType {
    static let epub = UTType(filenameExtension: "epub")!
}

#Preview {
    LibraryView()
}
