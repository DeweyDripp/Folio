import CryptoKit
import Foundation
import PDFKit
import ReadiumShared
import UIKit

enum ImportedBookLoader {
    nonisolated static func fingerprint(for url: URL) throws -> String {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }
        return try fileFingerprint(for: url)
    }

    static func load(from url: URL, fingerprint suppliedFingerprint: String? = nil) async throws -> Book {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let title = url.deletingPathExtension().lastPathComponent
        let fingerprint = try suppliedFingerprint ?? fileFingerprint(for: url)

        if url.pathExtension.lowercased() == "epub" {
            return try await loadEPUB(from: url, fallbackTitle: title, fingerprint: fingerprint)
        }

        if url.pathExtension.lowercased() == "pdf" {
            return try loadPDF(from: url, title: title, fingerprint: fingerprint)
        }

        return try loadText(from: url, title: title, fingerprint: fingerprint)
    }

    private static func loadEPUB(from url: URL, fallbackTitle: String, fingerprint: String) async throws -> Book {
        let id = UUID()
        let fileName = id.uuidString + ".epub"
        let savedURL = ImportedBookStore.booksDirectory.appending(path: fileName)
        let coverFileName = id.uuidString + ".jpg"
        let coverURL = ImportedBookStore.coversDirectory.appending(path: coverFileName)

        try FileManager.default.copyItem(at: url, to: savedURL)

        do {
            let publication = try await ReadiumService.shared.openPublication(at: savedURL)
            guard publication.conforms(to: .epub) else {
                throw ImportError.notAnEPUB
            }

            let authors = publication.metadata.authors.map(\.name).joined(separator: ", ")
            let cover = try? await publication.cover().get()
            let coverData = cover?.jpegData(compressionQuality: 0.8)
            if let coverData {
                try coverData.write(to: coverURL, options: .atomic)
            }

            return Book(
                id: id,
                title: publication.metadata.title ?? fallbackTitle,
                author: authors.isEmpty ? "Unknown Author" : authors,
                coverSymbol: "book.pages.fill",
                coverColorName: "indigo",
                pages: [],
                format: .epub,
                fileName: fileName,
                coverFileName: coverData == nil ? nil : coverFileName,
                fingerprint: fingerprint
            )
        } catch {
            try? FileManager.default.removeItem(at: savedURL)
            try? FileManager.default.removeItem(at: coverURL)
            throw error
        }
    }

    private static func loadPDF(from url: URL, title: String, fingerprint: String) throws -> Book {
        guard let document = PDFDocument(url: url) else {
            throw ImportError.unreadableFile
        }

        var pages: [String] = []
        pages.reserveCapacity(document.pageCount)
        for index in 0..<document.pageCount {
            autoreleasepool {
                if let text = document.page(at: index)?.string?.trimmedForReading, !text.isEmpty {
                    pages.append(text)
                }
            }
        }

        guard !pages.isEmpty else {
            throw ImportError.noReadableText
        }

        return importedBook(title: title, pages: pages, format: .pdf, fingerprint: fingerprint)
    }

    private static func loadText(from url: URL, title: String, fingerprint: String) throws -> Book {
        let text = try String(contentsOf: url, encoding: .utf8).trimmedForReading

        guard !text.isEmpty else {
            throw ImportError.noReadableText
        }

        return importedBook(title: title, pages: paginate(text), format: .text, fingerprint: fingerprint)
    }

    private static func importedBook(
        title: String,
        pages: [String],
        format: BookFormat,
        fingerprint: String
    ) -> Book {
        Book(
            title: title,
            author: "Imported Book",
            coverSymbol: "doc.text.fill",
            coverColorName: "orange",
            pages: pages,
            format: format,
            fingerprint: fingerprint
        )
    }

    nonisolated private static func fileFingerprint(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func paginate(_ text: String, targetLength: Int = 1_600) -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n")
        var pages: [String] = []
        var currentPage = ""

        for paragraph in paragraphs {
            let cleanParagraph = paragraph.trimmedForReading
            guard !cleanParagraph.isEmpty else { continue }

            let candidate = currentPage.isEmpty
                ? cleanParagraph
                : currentPage + "\n\n" + cleanParagraph

            if candidate.count <= targetLength || currentPage.isEmpty {
                currentPage = candidate
            } else {
                pages.append(currentPage)
                currentPage = cleanParagraph
            }
        }

        if !currentPage.isEmpty {
            pages.append(currentPage)
        }

        return pages
    }
}

private extension String {
    var trimmedForReading: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum ImportError: LocalizedError {
    case unreadableFile
    case noReadableText
    case notAnEPUB

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "Folio couldn’t open that file."
        case .noReadableText:
            "This file doesn’t contain readable text. Scanned PDFs aren’t supported yet."
        case .notAnEPUB:
            "That file isn’t a valid EPUB publication."
        }
    }
}
