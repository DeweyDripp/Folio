import Combine
import Foundation

struct ReadingProgress: Codable, Equatable, Identifiable {
    let bookID: UUID
    var pageIndex: Int?
    var locatorJSON: String?
    var fraction: Double
    var chapterTitle: String?
    var updatedAt: Date

    var id: UUID { bookID }
}

@MainActor
final class ReadingProgressStore: ObservableObject {
    static let shared = ReadingProgressStore()

    @Published private(set) var entries: [UUID: ReadingProgress] = [:]
    @Published private(set) var errorMessage: String?

    private let fileURL: URL
    private let backupURL: URL

    init(fileURL: URL = URL.documentsDirectory.appending(path: "ReadingProgress.json")) {
        self.fileURL = fileURL
        self.backupURL = fileURL
            .deletingPathExtension()
            .appendingPathExtension("backup.json")
        load()
    }

    func progress(for bookID: UUID) -> ReadingProgress? {
        entries[bookID]
    }

    func markOpened(_ bookID: UUID) {
        var progress = entries[bookID] ?? ReadingProgress(
            bookID: bookID,
            pageIndex: nil,
            locatorJSON: nil,
            fraction: 0,
            chapterTitle: nil,
            updatedAt: Date()
        )
        progress.updatedAt = Date()
        store(progress)
    }

    func savePage(_ pageIndex: Int, pageCount: Int, title: String, for bookID: UUID) {
        let safeCount = max(1, pageCount)
        let fraction = min(1, max(0, Double(pageIndex + 1) / Double(safeCount)))
        store(
            ReadingProgress(
                bookID: bookID,
                pageIndex: pageIndex,
                locatorJSON: nil,
                fraction: fraction,
                chapterTitle: title,
                updatedAt: Date()
            )
        )
    }

    func saveEPUB(
        locatorJSON: String,
        fraction: Double?,
        chapterTitle: String?,
        for bookID: UUID
    ) {
        store(
            ReadingProgress(
                bookID: bookID,
                pageIndex: nil,
                locatorJSON: locatorJSON,
                fraction: min(1, max(0, fraction ?? entries[bookID]?.fraction ?? 0)),
                chapterTitle: chapterTitle,
                updatedAt: Date()
            )
        )
    }

    func remove(for bookID: UUID) {
        entries.removeValue(forKey: bookID)
        persist()
    }

    func clearError() {
        errorMessage = nil
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let saved = try JSONDecoder().decode([ReadingProgress].self, from: data)
            entries = Dictionary(uniqueKeysWithValues: saved.map { ($0.bookID, $0) })
        } catch {
            do {
                let backupData = try Data(contentsOf: backupURL)
                let saved = try JSONDecoder().decode([ReadingProgress].self, from: backupData)
                entries = Dictionary(uniqueKeysWithValues: saved.map { ($0.bookID, $0) })
                try backupData.write(to: fileURL, options: .atomic)
            } catch {
                errorMessage = "Folio couldn’t load your saved reading progress. Your books are still safe."
            }
        }
    }

    private func store(_ progress: ReadingProgress) {
        entries[progress.bookID] = progress
        persist()
    }

    private func persist() {
        do {
            let saved = entries.values.sorted { $0.updatedAt < $1.updatedAt }
            let data = try JSONEncoder().encode(saved)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let currentData = try Data(contentsOf: fileURL)
                try currentData.write(to: backupURL, options: .atomic)
            }
            try data.write(to: fileURL, options: .atomic)
            errorMessage = nil
        } catch {
            errorMessage = "Folio couldn’t save your reading progress. Check that your device has available storage."
        }
    }
}
