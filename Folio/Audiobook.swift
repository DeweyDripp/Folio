import Foundation

struct AudiobookChapter: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let fileName: String
}

struct Audiobook: Identifiable, Codable {
    let id: UUID
    let title: String
    let author: String
    let chapters: [AudiobookChapter]
    let importedAt: Date
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
}
