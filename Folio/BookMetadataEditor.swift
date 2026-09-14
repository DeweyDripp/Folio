import SwiftUI

struct BookMetadataEditor: View {
    let book: Book
    let save: (Book) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var author: String
    @State private var shelf: String
    @State private var publisher: String
    @State private var publishYear: String
    @State private var language: String
    @State private var isbn: String
    @State private var description: String
    @State private var isLookingUp = false
    @State private var lookupMessage: String?

    init(book: Book, save: @escaping (Book) -> Void) {
        self.book = book
        self.save = save
        _title = State(initialValue: book.title)
        _author = State(initialValue: book.author)
        _shelf = State(initialValue: book.normalizedShelf ?? "")
        _publisher = State(initialValue: book.publisher ?? "")
        _publishYear = State(initialValue: book.publishYear.map(String.init) ?? "")
        _language = State(initialValue: book.language ?? "")
        _isbn = State(initialValue: book.isbn ?? "")
        _description = State(initialValue: book.description ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Book Details") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)

                    TextField("Author", text: $author)
                        .textInputAutocapitalization(.words)

                    TextField("Shelf (optional)", text: $shelf)
                        .textInputAutocapitalization(.words)

                    TextField("Publisher (optional)", text: $publisher)
                        .textInputAutocapitalization(.words)

                    TextField("Publication year", text: $publishYear)
                        .keyboardType(.numberPad)

                    TextField("Language", text: $language)
                        .textInputAutocapitalization(.words)

                    TextField("ISBN", text: $isbn)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.asciiCapable)
                }

                Section {
                    TextEditor(text: $description)
                        .frame(minHeight: 90)
                } header: {
                    Text("Description")
                }

                Section {
                    Button {
                        lookupMetadata()
                    } label: {
                        HStack {
                            Label("Find Metadata Online", systemImage: "magnifyingglass")
                            Spacer()
                            if isLookingUp {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLookingUp || (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isbn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

                    if let lookupMessage {
                        Text(lookupMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Open Library")
                } footer: {
                    Text("Folio searches Open Library one book at a time. Review the fields before saving.")
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
                                author: cleanAuthor.isEmpty ? "Unknown Author" : cleanAuthor,
                                shelf: shelf,
                                publisher: cleanOptional(publisher),
                                publishYear: Int(publishYear.trimmingCharacters(in: .whitespacesAndNewlines)),
                                language: cleanOptional(language),
                                isbn: cleanOptional(isbn),
                                description: cleanOptional(description)
                            )
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func lookupMetadata() {
        isLookingUp = true
        lookupMessage = nil

        Task {
            do {
                let suggestion = try await OpenLibraryService.lookup(
                    title: title,
                    author: author,
                    isbn: isbn
                )
                await MainActor.run {
                    if let suggestion {
                        title = suggestion.title ?? title
                        author = suggestion.author ?? author
                        publisher = suggestion.publisher ?? publisher
                        if let year = suggestion.publishYear { publishYear = String(year) }
                        language = suggestion.language ?? language
                        isbn = suggestion.isbn ?? isbn
                        lookupMessage = "Metadata found. Review it before saving."
                    } else {
                        lookupMessage = "No matching book was found. Try adding an ISBN."
                    }
                    isLookingUp = false
                }
            } catch {
                await MainActor.run {
                    lookupMessage = "The online lookup failed. You can still edit the fields manually."
                    isLookingUp = false
                }
            }
        }
    }

    private func cleanOptional(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
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
