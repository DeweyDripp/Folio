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
    @State private var suggestions: [OpenLibraryMetadata] = []
    @State private var showsSuggestions = false

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
                Section {
                    Text("Edit these fields manually, or use Open Library below to find matching editions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Book Details")
                }

                Section {
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
                    Text("Folio searches Open Library and shows several matches. Choose the right edition, then review the fields before saving.")
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
        .sheet(isPresented: $showsSuggestions) {
            OpenLibraryMatchPicker(matches: suggestions) { match in
                apply(match)
                showsSuggestions = false
            }
        }
    }

    private func lookupMetadata() {
        isLookingUp = true
        lookupMessage = nil

        Task {
            do {
                let matches = try await OpenLibraryService.search(
                    title: title,
                    author: author,
                    isbn: isbn
                )
                await MainActor.run {
                    if matches.isEmpty {
                        lookupMessage = "No matching book was found. Try adding an ISBN."
                    } else {
                        suggestions = matches
                        lookupMessage = "Choose the matching edition."
                        showsSuggestions = true
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

    private func apply(_ match: OpenLibraryMetadata) {
        title = match.title ?? title
        author = match.author ?? author
        publisher = match.publisher ?? publisher
        if let year = match.publishYear { publishYear = String(year) }
        language = match.language ?? language
        isbn = match.isbn ?? isbn
    }

    private func cleanOptional(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}

private struct OpenLibraryMatchPicker: View {
    let matches: [OpenLibraryMetadata]
    let select: (OpenLibraryMetadata) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(matches) { match in
                Button {
                    select(match)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(match.title ?? "Untitled")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(match.author ?? "Unknown author")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text([match.publisher, match.publishYear.map(String.init), match.isbn].compactMap { $0 }.joined(separator: " • "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Choose Edition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
