import SwiftUI

struct BookMetadataEditor: View {
    let book: Book
    let save: (Book) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var author: String

    init(book: Book, save: @escaping (Book) -> Void) {
        self.book = book
        self.save = save
        _title = State(initialValue: book.title)
        _author = State(initialValue: book.author)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Book Details") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)

                    TextField("Author", text: $author)
                        .textInputAutocapitalization(.words)
                }

                Section("File Information") {
                    LabeledContent("Format", value: book.bookFormat.displayName)

                    if let fileName = book.fileName {
                        LabeledContent("File", value: fileName)
                    }
                }
            }
            .navigationTitle("Book Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
                        save(
                            book.updatingMetadata(
                                title: cleanTitle,
                                author: cleanAuthor.isEmpty ? "Unknown Author" : cleanAuthor
                            )
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private extension BookFormat {
    var displayName: String {
        switch self {
        case .text: "Text"
        case .pdf: "PDF"
        case .epub: "EPUB"
        }
    }
}
