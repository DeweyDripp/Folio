import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @State private var importedBooks = ImportedBookStore.load()
    @State private var isShowingImporter = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var bookToEdit: Book?
    @State private var bookToDelete: Book?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 24)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if importedBooks.isEmpty {
                    ContentUnavailableView {
                        Label("Your Library Is Empty", systemImage: "books.vertical")
                    } description: {
                        Text("Tap the plus button to import an EPUB, PDF, or text file.")
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 28) {
                            ForEach(importedBooks) { book in
                                NavigationLink {
                                    ReaderView(book: book)
                                } label: {
                                    BookCoverView(book: book)
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

                ToolbarItem(placement: .primaryAction) {
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
            .alert("Couldn’t Import Book", isPresented: isShowingImportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importError ?? "Please try another file.")
            }
        }
    }

    private var isShowingImportError: Binding<Bool> {
        Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )
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

        importedBooks[index] = updatedBook
        ImportedBookStore.save(importedBooks)
    }

    private func deleteBook(_ book: Book) {
        importedBooks.removeAll { $0.id == book.id }
        ImportedBookStore.save(importedBooks)
        ImportedBookStore.removeImportedFile(for: book)
        ReaderBookmarkStore.removeAll(for: book.id)
        ReaderHighlightStore.removeAll(for: book.id)
        EPUBProgressStore.remove(for: book.id)
        bookToDelete = nil
    }

    @MainActor
    private func importBook(from result: Result<URL, Error>) async {
        isImporting = true
        defer { isImporting = false }

        do {
            let url = try result.get()
            let book = try await ImportedBookLoader.load(from: url)
            importedBooks.insert(book, at: 0)
            ImportedBookStore.save(importedBooks)
        } catch {
            importError = error.localizedDescription
        }
    }
}

private extension UTType {
    static let epub = UTType(filenameExtension: "epub")!
}

#Preview {
    LibraryView()
}
