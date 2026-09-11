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

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        coverSymbol: String,
        coverColorName: String,
        pages: [String],
        format: BookFormat? = .text,
        fileName: String? = nil,
        coverData: Data? = nil
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
    }

    var bookFormat: BookFormat {
        format ?? .text
    }
}
