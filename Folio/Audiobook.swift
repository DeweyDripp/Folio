import AVFoundation
import Foundation

struct AudiobookChapter: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let fileName: String
    let duration: TimeInterval?
    let fingerprint: String?
}

struct Audiobook: Identifiable, Codable {
    let id: UUID
    let title: String
    let author: String
    let chapters: [AudiobookChapter]
    let importedAt: Date
    let coverData: Data?
}

struct AudiobookBookmark: Identifiable, Codable, Hashable {
    let id: UUID
    let chapterIndex: Int
    let time: TimeInterval
    var note: String
    let createdAt: Date
}

enum AudiobookStore {
    private static let fileURL = URL.documentsDirectory.appending(path: "Audiobooks.json")
    static var audioDirectory: URL {
        let url = URL.documentsDirectory.appending(path: "Audiobooks", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load() throws -> [Audiobook] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([Audiobook].self, from: Data(contentsOf: fileURL))
    }

    static func save(_ books: [Audiobook]) throws {
        try JSONEncoder().encode(books).write(to: fileURL, options: .atomic)
    }

    static func removeFiles(for audiobook: Audiobook) {
        for chapter in audiobook.chapters {
            try? FileManager.default.removeItem(at: audioDirectory.appending(path: chapter.fileName))
        }
    }

    static func progress(for audiobook: Audiobook) -> Double {
        guard !audiobook.chapters.isEmpty else { return 0 }
        var totalDuration = 0.0
        var listenedDuration = 0.0

        for (index, chapter) in audiobook.chapters.enumerated() {
            guard let chapterDuration = duration(for: chapter), chapterDuration > 0 else { continue }
            totalDuration += chapterDuration
            let saved = UserDefaults.standard.double(forKey: positionKey(for: audiobook.id, chapter: index))
            listenedDuration += min(max(0, saved), chapterDuration)
        }

        guard totalDuration > 0 else { return 0 }
        return min(1, listenedDuration / totalDuration)
    }

    static func positionKey(for audiobookID: UUID, chapter: Int) -> String {
        "audiobook-\(audiobookID.uuidString)-chapter-\(chapter)"
    }

    static func bookmarks(for audiobookID: UUID) -> [AudiobookBookmark] {
        guard let data = UserDefaults.standard.data(forKey: "audiobook-\(audiobookID.uuidString)-bookmarks") else { return [] }
        return (try? JSONDecoder().decode([AudiobookBookmark].self, from: data)) ?? []
    }

    static func saveBookmarks(_ bookmarks: [AudiobookBookmark], for audiobookID: UUID) {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: "audiobook-\(audiobookID.uuidString)-bookmarks")
        }
    }

    static func isFavorite(_ audiobookID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: "audiobook-\(audiobookID.uuidString)-favorite")
    }

    static func setFavorite(_ favorite: Bool, for audiobookID: UUID) {
        UserDefaults.standard.set(favorite, forKey: "audiobook-\(audiobookID.uuidString)-favorite")
    }

    static func shelf(for audiobookID: UUID) -> String? {
        UserDefaults.standard.string(forKey: "audiobook-\(audiobookID.uuidString)-shelf")
    }

    static func setShelf(_ shelf: String?, for audiobookID: UUID) {
        let key = "audiobook-\(audiobookID.uuidString)-shelf"
        if let shelf, !shelf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.set(shelf, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func markPlayed(_ audiobookID: UUID) {
        UserDefaults.standard.set(Date(), forKey: "audiobook-\(audiobookID.uuidString)-last-played")
    }

    static func lastPlayed(_ audiobookID: UUID) -> Date? {
        UserDefaults.standard.object(forKey: "audiobook-\(audiobookID.uuidString)-last-played") as? Date
    }

    private static func duration(for chapter: AudiobookChapter) -> TimeInterval? {
        if let duration = chapter.duration { return duration }
        let url = audioDirectory.appending(path: chapter.fileName)
        return try? AVAudioPlayer(contentsOf: url).duration
    }

}
