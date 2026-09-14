import Foundation

enum ImportedBookStore {
    private static let libraryFileName = "ImportedBooks.json"

    static func load() throws -> [Book] {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            return []
        }

        var books: [Book]
        do {
            let data = try Data(contentsOf: libraryURL)
            books = try JSONDecoder().decode([Book].self, from: data)
        } catch {
            guard FileManager.default.fileExists(atPath: backupURL.path) else { throw error }
            let backupData = try Data(contentsOf: backupURL)
            books = try JSONDecoder().decode([Book].self, from: backupData)
            try backupData.write(to: libraryURL, options: .atomic)
        }
        var migratedLibrary = false

        // Older Folio versions embedded every cover inside ImportedBooks.json.
        // Move those images into their own files as the library is loaded.
        for index in books.indices {
            guard let coverData = books[index].coverData else { continue }
            let fileName = books[index].id.uuidString + ".jpg"
            try coverData.write(to: coversDirectory.appending(path: fileName), options: .atomic)
            books[index] = books[index].storingCover(in: fileName)
            migratedLibrary = true
        }

        // EPUB files are retained by Folio, so older imports can gain duplicate
        // detection without asking the reader to import them again.
        for index in books.indices {
            guard books[index].fingerprint == nil,
                  let fileName = books[index].fileName
            else {
                continue
            }
            let fileURL = booksDirectory.appending(path: fileName)
            guard let fingerprint = try? ImportedBookLoader.fingerprint(for: fileURL) else { continue }
            books[index] = books[index].storingFingerprint(fingerprint)
            migratedLibrary = true
        }

        if migratedLibrary {
            try save(books)
        }

        return books
    }

    static func save(_ books: [Book]) throws {
        let data = try JSONEncoder().encode(books)
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            let currentData = try Data(contentsOf: libraryURL)
            try currentData.write(to: backupURL, options: .atomic)
        }
        try data.write(to: libraryURL, options: .atomic)
    }

    static func removeImportedFiles(for book: Book) throws {
        if let fileName = book.fileName {
            try removeIfPresent(booksDirectory.appending(path: fileName))
        }

        if let coverFileName = book.coverFileName {
            try removeIfPresent(coversDirectory.appending(path: coverFileName))
        }
    }

    static func coverData(for book: Book) -> Data? {
        if let coverData = book.coverData {
            return coverData
        }

        guard let fileName = book.coverFileName else { return nil }
        return try? Data(contentsOf: coversDirectory.appending(path: fileName))
    }

    static var booksDirectory: URL {
        directory(named: "Books")
    }

    static var coversDirectory: URL {
        directory(named: "Covers")
    }

    private static var libraryURL: URL {
        URL.documentsDirectory.appending(path: libraryFileName)
    }

    private static var backupURL: URL {
        URL.documentsDirectory.appending(path: "ImportedBooks.backup.json")
    }

    private static func directory(named name: String) -> URL {
        let url = URL.documentsDirectory.appending(path: name, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            assertionFailure("Folio could not create its \(name) directory: \(error)")
        }
        return url
    }

    private static func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
