import Foundation

struct FolioBackup: Codable {
    let createdAt: Date
    let books: [Book]
    let progress: [ReadingProgress]
    let bookmarks: [UUID: [ReaderBookmark]]
    let highlights: [UUID: [ReaderHighlight]]
    let bookFiles: [UUID: Data]
    let coverFiles: [UUID: Data]

    init(
        createdAt: Date,
        books: [Book],
        progress: [ReadingProgress],
        bookmarks: [UUID: [ReaderBookmark]],
        highlights: [UUID: [ReaderHighlight]],
        bookFiles: [UUID: Data] = [:],
        coverFiles: [UUID: Data] = [:]
    ) {
        self.createdAt = createdAt
        self.books = books
        self.progress = progress
        self.bookmarks = bookmarks
        self.highlights = highlights
        self.bookFiles = bookFiles
        self.coverFiles = coverFiles
    }

    private enum CodingKeys: String, CodingKey {
        case createdAt
        case books
        case progress
        case bookmarks
        case highlights
        case bookFiles
        case coverFiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        books = try container.decode([Book].self, forKey: .books)
        progress = try container.decode([ReadingProgress].self, forKey: .progress)
        bookmarks = try container.decode([UUID: [ReaderBookmark]].self, forKey: .bookmarks)
        highlights = try container.decode([UUID: [ReaderHighlight]].self, forKey: .highlights)
        bookFiles = try container.decodeIfPresent([UUID: Data].self, forKey: .bookFiles) ?? [:]
        coverFiles = try container.decodeIfPresent([UUID: Data].self, forKey: .coverFiles) ?? [:]
    }
}

@MainActor
enum FolioBackupService {
    static func makeBackup(books: [Book]) throws -> URL {
        let backup = FolioBackup(
            createdAt: Date(),
            books: books,
            progress: Array(ReadingProgressStore.shared.entries.values),
            bookmarks: Dictionary(uniqueKeysWithValues: books.map { ($0.id, ReaderBookmarkStore(bookID: $0.id).bookmarks) }),
            highlights: Dictionary(uniqueKeysWithValues: books.map { ($0.id, ReaderHighlightStore(bookID: $0.id).highlights) }),
            bookFiles: fileData(for: books, fileName: \.fileName, directory: ImportedBookStore.booksDirectory),
            coverFiles: fileData(for: books, fileName: \.coverFileName, directory: ImportedBookStore.coversDirectory)
        )
        let url = FileManager.default.temporaryDirectory.appending(path: "Folio-Backup.json")
        try JSONEncoder().encode(backup).write(to: url, options: .atomic)
        return url
    }

    static func restore(from data: Data) throws {
        let backup = try JSONDecoder().decode(FolioBackup.self, from: data)
        try restoreFiles(from: backup)
        try ImportedBookStore.save(backup.books)
        ReadingProgressStore.shared.restore(backup.progress)
        for (bookID, bookmarks) in backup.bookmarks { ReaderBookmarkStore.restore(bookmarks, for: bookID) }
        for (bookID, highlights) in backup.highlights { ReaderHighlightStore.restore(highlights, for: bookID) }
        NotificationCenter.default.post(name: .folioLibraryDidChange, object: nil)
    }

    private static func fileData(for books: [Book], fileName: KeyPath<Book, String?>, directory: URL) -> [UUID: Data] {
        Dictionary(uniqueKeysWithValues: books.compactMap { book in
            guard let name = book[keyPath: fileName],
                  let data = try? Data(contentsOf: directory.appending(path: name))
            else {
                return nil
            }
            return (book.id, data)
        })
    }

    private static func restoreFiles(from backup: FolioBackup) throws {
        for book in backup.books {
            if let fileName = book.fileName, let data = backup.bookFiles[book.id] {
                try data.write(to: ImportedBookStore.booksDirectory.appending(path: fileName), options: .atomic)
            }
            if let coverFileName = book.coverFileName, let data = backup.coverFiles[book.id] {
                try data.write(to: ImportedBookStore.coversDirectory.appending(path: coverFileName), options: .atomic)
            }
        }
    }
}

extension Notification.Name { static let folioLibraryDidChange = Notification.Name("folio-library-did-change") }
