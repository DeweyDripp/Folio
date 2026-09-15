import Combine
import Foundation

enum ReaderHighlightColor: String, Codable, CaseIterable, Identifiable {
    case yellow
    case pink
    case green
    case blue

    var id: Self { self }

    var title: String { rawValue.capitalized }
}

struct ReaderHighlight: Codable, Identifiable, Hashable {
    let id: UUID
    let locatorJSON: String
    let text: String
    var note: String
    var color: ReaderHighlightColor
    let createdAt: Date
    let progression: Double?
}

@MainActor
final class ReaderHighlightStore: ObservableObject {
    @Published private(set) var highlights: [ReaderHighlight] = []

    private let bookID: UUID
    private let defaults: UserDefaults

    init(bookID: UUID, defaults: UserDefaults = .standard) {
        self.bookID = bookID
        self.defaults = defaults
        load()
    }

    static func removeAll(for bookID: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "reader-highlights-\(bookID.uuidString)")
    }

    static func restore(_ saved: [ReaderHighlight], for bookID: UUID, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: "reader-highlights-\(bookID.uuidString)")
    }

    func add(locatorJSON: String, text: String, progression: Double?) {
        guard !highlights.contains(where: { $0.locatorJSON == locatorJSON }) else { return }

        highlights.append(
            ReaderHighlight(
                id: UUID(),
                locatorJSON: locatorJSON,
                text: text,
                note: "",
                color: .yellow,
                createdAt: Date(),
                progression: progression
            )
        )
        sortAndSave()
    }

    func update(_ highlight: ReaderHighlight, note: String, color: ReaderHighlightColor) {
        guard let index = highlights.firstIndex(where: { $0.id == highlight.id }) else { return }
        highlights[index].note = note
        highlights[index].color = color
        save()
    }

    func remove(_ highlight: ReaderHighlight) {
        highlights.removeAll { $0.id == highlight.id }
        save()
    }

    private var storageKey: String {
        "reader-highlights-\(bookID.uuidString)"
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let savedHighlights = try? JSONDecoder().decode([ReaderHighlight].self, from: data)
        else {
            return
        }
        highlights = savedHighlights
    }

    private func sortAndSave() {
        highlights.sort {
            ($0.progression ?? 0) < ($1.progression ?? 0)
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(highlights) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
