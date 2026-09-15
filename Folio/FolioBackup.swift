import Foundation

struct FolioBackup: Codable {
    let createdAt: Date
    let books: [Book]
    let progress: [ReadingProgress]
    let bookmarks: [UUID: [ReaderBookmark]]
    let highlights: [UUID: [ReaderHighlight]]
}

@MainActor
enum FolioBackupService {
    static func makeBackup(books: [Book]) throws -> URL {
        let backup = FolioBackup(createdAt: Date(), books: books,
            progress: Array(ReadingProgressStore.shared.entries.values),
            bookmarks: Dictionary(uniqueKeysWithValues: books.map { ($0.id, ReaderBookmarkStore(bookID: $0.id).bookmarks) }),
            highlights: Dictionary(uniqueKeysWithValues: books.map { ($0.id, ReaderHighlightStore(bookID: $0.id).highlights) }))
        let url = FileManager.default.temporaryDirectory.appending(path: "Folio-Backup.json")
        try JSONEncoder().encode(backup).write(to: url, options: .atomic)
        return url
    }

    static func restore(from data: Data) throws {
        let backup = try JSONDecoder().decode(FolioBackup.self, from: data)
        try ImportedBookStore.save(backup.books)
        ReadingProgressStore.shared.restore(backup.progress)
        for (bookID, bookmarks) in backup.bookmarks { ReaderBookmarkStore.restore(bookmarks, for: bookID) }
        for (bookID, highlights) in backup.highlights { ReaderHighlightStore.restore(highlights, for: bookID) }
        NotificationCenter.default.post(name: .folioLibraryDidChange, object: nil)
    }
}

extension Notification.Name { static let folioLibraryDidChange = Notification.Name("folio-library-did-change") }
