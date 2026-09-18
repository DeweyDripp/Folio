import Foundation

enum LibraryImportValidator {
    static func containsDuplicateBook(fingerprint: String, in books: [Book]) -> Bool {
        books.contains { $0.fingerprint == fingerprint }
    }

    static func containsDuplicateAudiobookChapter(fingerprint: String, in audiobooks: [Audiobook]) -> Bool {
        audiobooks.flatMap(\.chapters).contains { $0.fingerprint == fingerprint }
    }

    static func existingAudiobookFingerprints(in audiobooks: [Audiobook]) -> Set<String> {
        Set(audiobooks.flatMap(\.chapters).compactMap(\.fingerprint))
    }

    static func canInsertAudiobookFingerprint(_ fingerprint: String, into seenFingerprints: inout Set<String>) -> Bool {
        seenFingerprints.insert(fingerprint).inserted
    }
}
