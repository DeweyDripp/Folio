import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @State private var importedBooks = ImportedBookStore.load()
    @State private var isShowingImporter = false
    @State private var isImporting = false
    @State private var importError: String?

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
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Library")
            .toolbar {
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
            .overlay {
                if isImporting {
                    ProgressView("Importing book…")
                        .padding(22)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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
