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
}
