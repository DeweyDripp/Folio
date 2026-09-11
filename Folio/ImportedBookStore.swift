import Foundation

enum ImportedBookStore {
    private static let fileName = "ImportedBooks.json"

    static func load() -> [Book] {
        guard let data = try? Data(contentsOf: fileURL),
              let books = try? JSONDecoder().decode([Book].self, from: data) else {
            return []
        }

        return books
    }

    static func save(_ books: [Book]) {
        guard let data = try? JSONEncoder().encode(books) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func removeImportedFile(for book: Book) {
        guard let fileName = book.fileName else { return }
        let fileURL = booksDirectory.appending(path: fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    static var booksDirectory: URL {
        let directory = URL.documentsDirectory.appending(path: "Books", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static var fileURL: URL {
        URL.documentsDirectory.appending(path: fileName)
    }
}
