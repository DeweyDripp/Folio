//
//  FolioTests.swift
//  FolioTests
//
//  Created by Ryan Ramirez on 9/10/26.
//

import Foundation
import Testing
@testable import Folio

struct FolioTests {
    @MainActor
    @Test func olderBookDataStillLoads() throws {
        let id = UUID()
        let oldJSON = """
        {
          "id": "\(id.uuidString)",
          "title": "An Older Book",
          "author": "Folio",
          "coverSymbol": "book",
          "coverColorName": "indigo",
          "pages": ["Page one"],
          "format": "text"
        }
        """

        let book = try JSONDecoder().decode(Book.self, from: Data(oldJSON.utf8))

        #expect(book.id == id)
        #expect(book.title == "An Older Book")
        #expect(book.fingerprint == nil)
        #expect(book.normalizedShelf == nil)
    }

    @Test func librarySortsTitlesAndRecentReading() {
        let older = Book(
            title: "Zulu",
            author: "Writer B",
            coverSymbol: "book",
            coverColorName: "indigo",
            pages: ["One"],
            importedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = Book(
            title: "Alpha",
            author: "Writer A",
            coverSymbol: "book",
            coverColorName: "indigo",
            pages: ["One"],
            importedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(LibrarySortOption.title.sort([older, newer]) { _ in nil }.map(\.title) == ["Alpha", "Zulu"])

        let recent = LibrarySortOption.recent.sort([older, newer]) { id in
            id == older.id ? Date(timeIntervalSince1970: 300) : nil
        }
        #expect(recent.map(\.title) == ["Zulu", "Alpha"])
    }

    @MainActor
    @Test func readingProgressSurvivesRelaunch() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "FolioProgress-\(UUID().uuidString).json")
        let backupURL = fileURL.deletingPathExtension().appendingPathExtension("backup.json")
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: backupURL)
        }

        let bookID = UUID()
        let firstStore = ReadingProgressStore(fileURL: fileURL)
        firstStore.savePage(24, pageCount: 100, title: "Page 25", for: bookID)

        let relaunchedStore = ReadingProgressStore(fileURL: fileURL)
        let progress = relaunchedStore.progress(for: bookID)
        #expect(progress?.pageIndex == 24)
        #expect(progress?.fraction == 0.25)
        #expect(progress?.chapterTitle == "Page 25")

        relaunchedStore.savePage(49, pageCount: 100, title: "Page 50", for: bookID)
        try Data("damaged".utf8).write(to: fileURL)
        let recoveredStore = ReadingProgressStore(fileURL: fileURL)
        #expect(recoveredStore.progress(for: bookID)?.pageIndex == 24)
    }

    @Test func identicalFilesHaveTheSameFingerprint() throws {
        let firstURL = FileManager.default.temporaryDirectory
            .appending(path: "FolioFingerprint-\(UUID().uuidString).txt")
        let secondURL = FileManager.default.temporaryDirectory
            .appending(path: "FolioFingerprint-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }

        try Data("A small book".utf8).write(to: firstURL)
        try Data("A small book".utf8).write(to: secondURL)

        #expect(
            try ImportedBookLoader.fingerprint(for: firstURL)
                == ImportedBookLoader.fingerprint(for: secondURL)
        )
    }

    @Test func duplicateImportsAreDetectedByFingerprint() {
        let duplicateFingerprint = "duplicate-fingerprint"
        let book = Book(
            title: "Known Book",
            author: "Folio",
            coverSymbol: "book",
            coverColorName: "indigo",
            pages: ["One"],
            fingerprint: duplicateFingerprint
        )
        let audiobook = Audiobook(
            id: UUID(),
            title: "Known Audiobook",
            author: "Folio",
            chapters: [
                AudiobookChapter(
                    id: UUID(),
                    title: "Chapter 1",
                    fileName: "chapter.mp3",
                    duration: 120,
                    fingerprint: duplicateFingerprint
                )
            ],
            importedAt: Date(),
            coverData: nil
        )

        #expect(LibraryImportValidator.containsDuplicateBook(fingerprint: duplicateFingerprint, in: [book]))
        #expect(!LibraryImportValidator.containsDuplicateBook(fingerprint: "new-fingerprint", in: [book]))
        #expect(LibraryImportValidator.containsDuplicateAudiobookChapter(fingerprint: duplicateFingerprint, in: [audiobook]))
        #expect(!LibraryImportValidator.containsDuplicateAudiobookChapter(fingerprint: "new-fingerprint", in: [audiobook]))

        var seenFingerprints = LibraryImportValidator.existingAudiobookFingerprints(in: [audiobook])
        #expect(!LibraryImportValidator.canInsertAudiobookFingerprint(duplicateFingerprint, into: &seenFingerprints))
        #expect(LibraryImportValidator.canInsertAudiobookFingerprint("new-fingerprint", into: &seenFingerprints))
        #expect(!LibraryImportValidator.canInsertAudiobookFingerprint("new-fingerprint", into: &seenFingerprints))
    }

    @MainActor
    @Test func audiobookResumePositionSurvivesNewPlayer() throws {
        let audiobook = try makeAudiobook(duration: 2)
        clearAudiobookDefaults(for: audiobook)
        defer { cleanupAudiobook(audiobook) }

        let firstPlayer = AudiobookPlayerModel(audiobook: audiobook)
        firstPlayer.seek(toProgress: 0.5)
        firstPlayer.stop()

        let relaunchedPlayer = AudiobookPlayerModel(audiobook: audiobook)
        defer { relaunchedPlayer.stop() }

        #expect(relaunchedPlayer.elapsed > 0.8)
        #expect(relaunchedPlayer.progress > 0.35)
    }

    @MainActor
    @Test func audiobookBookmarksPersistAndCanBeJumpedTo() throws {
        let audiobook = try makeAudiobook(duration: 4)
        clearAudiobookDefaults(for: audiobook)
        defer { cleanupAudiobook(audiobook) }

        let firstPlayer = AudiobookPlayerModel(audiobook: audiobook)
        firstPlayer.seek(toProgress: 0.25)
        firstPlayer.addBookmark(note: "Good bit")
        firstPlayer.stop()

        let relaunchedPlayer = AudiobookPlayerModel(audiobook: audiobook)
        defer { relaunchedPlayer.stop() }

        #expect(relaunchedPlayer.bookmarks.count == 1)
        #expect(relaunchedPlayer.bookmarks.first?.note == "Good bit")

        if let bookmark = relaunchedPlayer.bookmarks.first {
            relaunchedPlayer.seek(toProgress: 0)
            relaunchedPlayer.jump(to: bookmark)
            #expect(relaunchedPlayer.elapsed > 0.8)
        }
    }

    @MainActor
    @Test func audiobookSpeedPersistsBetweenPlayers() throws {
        let audiobook = try makeAudiobook(duration: 1)
        clearAudiobookDefaults(for: audiobook)
        defer { cleanupAudiobook(audiobook) }

        let firstPlayer = AudiobookPlayerModel(audiobook: audiobook)
        firstPlayer.speed = 1.5
        firstPlayer.stop()

        let relaunchedPlayer = AudiobookPlayerModel(audiobook: audiobook)
        defer { relaunchedPlayer.stop() }

        #expect(relaunchedPlayer.speed == 1.5)
    }

    @MainActor
    @Test func audiobookSleepTimerStopsPlaybackAndClearsItself() async throws {
        let audiobook = try makeAudiobook(duration: 2)
        clearAudiobookDefaults(for: audiobook)
        defer { cleanupAudiobook(audiobook) }

        let player = AudiobookPlayerModel(audiobook: audiobook)
        defer { player.stop() }

        player.toggle()
        player.setSleepTimer(0.05)

        #expect(player.sleepTimerRemaining != nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        player.refresh()

        #expect(!player.isPlaying)
        #expect(player.sleepTimerRemaining == nil)
        #expect(player.sleepTimerLabel == "Sleep Timer")
    }

    private func makeAudiobook(duration: TimeInterval) throws -> Audiobook {
        let audiobookID = UUID()
        let fileName = "\(audiobookID.uuidString)-0.wav"
        let url = AudiobookStore.audioDirectory.appending(path: fileName)
        try silentWAVData(duration: duration).write(to: url, options: .atomic)

        return Audiobook(
            id: audiobookID,
            title: "Test Audiobook",
            author: "Folio Tests",
            chapters: [
                AudiobookChapter(
                    id: UUID(),
                    title: "Chapter 1",
                    fileName: fileName,
                    duration: duration,
                    fingerprint: "fingerprint-\(audiobookID.uuidString)"
                )
            ],
            importedAt: Date(),
            coverData: nil
        )
    }

    private func cleanupAudiobook(_ audiobook: Audiobook) {
        AudiobookStore.removeFiles(for: audiobook)
        clearAudiobookDefaults(for: audiobook)
    }

    private func clearAudiobookDefaults(for audiobook: Audiobook) {
        for chapterIndex in audiobook.chapters.indices {
            UserDefaults.standard.removeObject(forKey: AudiobookStore.positionKey(for: audiobook.id, chapter: chapterIndex))
        }
        UserDefaults.standard.removeObject(forKey: "audiobook-\(audiobook.id.uuidString)-bookmarks")
        UserDefaults.standard.removeObject(forKey: "audiobook-\(audiobook.id.uuidString)-speed")
        UserDefaults.standard.removeObject(forKey: "audiobook-\(audiobook.id.uuidString)-favorite")
        UserDefaults.standard.removeObject(forKey: "audiobook-\(audiobook.id.uuidString)-shelf")
        UserDefaults.standard.removeObject(forKey: "audiobook-\(audiobook.id.uuidString)-last-played")
    }

    private func silentWAVData(duration: TimeInterval, sampleRate: UInt32 = 8_000) -> Data {
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let sampleCount = UInt32(duration * Double(sampleRate))
        let dataSize = sampleCount * UInt32(channelCount) * bytesPerSample
        let byteRate = sampleRate * UInt32(channelCount) * bytesPerSample
        let blockAlign = channelCount * (bitsPerSample / 8)
        var data = Data()

        data.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(36 + dataSize, to: &data)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(channelCount, to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(byteRate, to: &data)
        appendLittleEndian(blockAlign, to: &data)
        appendLittleEndian(bitsPerSample, to: &data)
        data.append(contentsOf: "data".utf8)
        appendLittleEndian(dataSize, to: &data)
        data.append(Data(repeating: 0, count: Int(dataSize)))

        return data
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
