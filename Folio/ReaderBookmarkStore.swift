import Combine
import Foundation

struct ReaderChapter: Identifiable {
    let id: String
    let title: String
    let depth: Int
}

struct ReaderBookmark: Identifiable, Codable {
    let id: UUID
    let title: String
    let createdAt: Date
    let locationJSON: String?
    let pageIndex: Int?
}

@MainActor
final class ReaderBookmarkStore: ObservableObject {
    @Published private(set) var bookmarks: [ReaderBookmark] = []

    private let bookID: UUID
    private let defaults: UserDefaults

    init(bookID: UUID, defaults: UserDefaults = .standard) {
        self.bookID = bookID
        self.defaults = defaults
        load()
    }

    func containsPage(_ pageIndex: Int) -> Bool {
        bookmarks.contains { $0.pageIndex == pageIndex }
    }

    func containsLocation(_ locationJSON: String) -> Bool {
        bookmarks.contains { $0.locationJSON == locationJSON }
    }

    func togglePage(_ pageIndex: Int) {
        if let bookmark = bookmarks.first(where: { $0.pageIndex == pageIndex }) {
            remove(bookmark)
        } else {
            bookmarks.append(
                ReaderBookmark(
                    id: UUID(),
                    title: "Page \(pageIndex + 1)",
                    createdAt: Date(),
                    locationJSON: nil,
                    pageIndex: pageIndex
                )
            )
            save()
        }
    }

    func toggleLocation(json: String, title: String) {
        if let bookmark = bookmarks.first(where: { $0.locationJSON == json }) {
            remove(bookmark)
        } else {
            bookmarks.append(
                ReaderBookmark(
                    id: UUID(),
                    title: title,
                    createdAt: Date(),
                    locationJSON: json,
                    pageIndex: nil
                )
            )
            save()
        }
    }

    func remove(_ bookmark: ReaderBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        save()
    }

    private var storageKey: String {
        "reader-bookmarks-\(bookID.uuidString)"
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let savedBookmarks = try? JSONDecoder().decode([ReaderBookmark].self, from: data)
        else {
            return
        }

        bookmarks = savedBookmarks
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
