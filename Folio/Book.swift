import Foundation

enum BookFormat: String, Codable {
    case text
    case pdf
    case epub
}

struct Book: Identifiable, Codable {
    let id: UUID
    let title: String
    let author: String
    let coverSymbol: String
    let coverColorName: String
    let pages: [String]
    let format: BookFormat?
    let fileName: String?
    let coverData: Data?
    let coverFileName: String?
    let fingerprint: String?
    let importedAt: Date?
    let shelf: String?
    let publisher: String?
    let publishYear: Int?
    let language: String?
    let isbn: String?
    let description: String?

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        coverSymbol: String,
        coverColorName: String,
        pages: [String],
        format: BookFormat? = .text,
        fileName: String? = nil,
        coverData: Data? = nil,
        coverFileName: String? = nil,
        fingerprint: String? = nil,
        importedAt: Date? = Date(),
        shelf: String? = nil,
        publisher: String? = nil,
        publishYear: Int? = nil,
        language: String? = nil,
        isbn: String? = nil,
        description: String? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverSymbol = coverSymbol
        self.coverColorName = coverColorName
        self.pages = pages
        self.format = format
        self.fileName = fileName
        self.coverData = coverData
        self.coverFileName = coverFileName
        self.fingerprint = fingerprint
        self.importedAt = importedAt
        self.shelf = shelf
        self.publisher = publisher
        self.publishYear = publishYear
        self.language = language
        self.isbn = isbn
        self.description = description
    }

    var bookFormat: BookFormat {
        format ?? .text
    }

    var importDate: Date {
        importedAt ?? .distantPast
    }

    var normalizedShelf: String? {
        let value = shelf?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    func updatingMetadata(
        title: String,
        author: String,
        shelf: String?,
        publisher: String? = nil,
        publishYear: Int? = nil,
        language: String? = nil,
        isbn: String? = nil,
        description: String? = nil
    ) -> Book {
        Book(
            id: id,
            title: title,
            author: author,
            coverSymbol: coverSymbol,
            coverColorName: coverColorName,
            pages: pages,
            format: format,
            fileName: fileName,
            coverData: coverData,
            coverFileName: coverFileName,
            fingerprint: fingerprint,
            importedAt: importedAt,
            shelf: shelf,
            publisher: publisher,
            publishYear: publishYear,
            language: language,
            isbn: isbn,
            description: description
        )
    }

    func storingCover(in fileName: String) -> Book {
        Book(
            id: id,
            title: title,
            author: author,
            coverSymbol: coverSymbol,
            coverColorName: coverColorName,
            pages: pages,
            format: format,
            fileName: self.fileName,
            coverData: nil,
            coverFileName: fileName,
            fingerprint: fingerprint,
            importedAt: importedAt,
            shelf: shelf,
            publisher: publisher,
            publishYear: publishYear,
            language: language,
            isbn: isbn,
            description: description
        )
    }

    func storingFingerprint(_ value: String) -> Book {
        Book(
            id: id,
            title: title,
            author: author,
            coverSymbol: coverSymbol,
            coverColorName: coverColorName,
            pages: pages,
            format: format,
            fileName: fileName,
            coverData: coverData,
            coverFileName: coverFileName,
            fingerprint: value,
            importedAt: importedAt,
            shelf: shelf,
            publisher: publisher,
            publishYear: publishYear,
            language: language,
            isbn: isbn,
            description: description
        )
    }
}
