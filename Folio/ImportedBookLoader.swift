import Foundation
import PDFKit
import ReadiumShared
import UIKit

enum ImportedBookLoader {
    static func load(from url: URL) async throws -> Book {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let title = url.deletingPathExtension().lastPathComponent

        if url.pathExtension.lowercased() == "epub" {
            return try await loadEPUB(from: url, fallbackTitle: title)
        }

        if url.pathExtension.lowercased() == "pdf" {
            return try loadPDF(from: url, title: title)
        }

        return try loadText(from: url, title: title)
    }

    private static func loadEPUB(from url: URL, fallbackTitle: String) async throws -> Book {
        let id = UUID()
        let fileName = id.uuidString + ".epub"
        let savedURL = ImportedBookStore.booksDirectory.appending(path: fileName)

        try FileManager.default.copyItem(at: url, to: savedURL)

        do {
            let publication = try await ReadiumService.shared.openPublication(at: savedURL)
            guard publication.conforms(to: .epub) else {
                throw ImportError.notAnEPUB
            }

            let authors = publication.metadata.authors.map(\.name).joined(separator: ", ")
            let cover = try? await publication.cover().get()

            return Book(
                id: id,
                title: publication.metadata.title ?? fallbackTitle,
                author: authors.isEmpty ? "Unknown Author" : authors,
                coverSymbol: "book.pages.fill",
                coverColorName: "indigo",
                pages: [],
                format: .epub,
                fileName: fileName,
                coverData: cover?.jpegData(compressionQuality: 0.8)
            )
        } catch {
            try? FileManager.default.removeItem(at: savedURL)
            throw error
        }
    }

    private static func loadPDF(from url: URL, title: String) throws -> Book {
        guard let document = PDFDocument(url: url) else {
            throw ImportError.unreadableFile
        }

        let pages = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string?.trimmedForReading }
            .filter { !$0.isEmpty }

        guard !pages.isEmpty else {
            throw ImportError.noReadableText
        }

        return importedBook(title: title, pages: pages, format: .pdf)
    }

    private static func loadText(from url: URL, title: String) throws -> Book {
        let text = try String(contentsOf: url, encoding: .utf8).trimmedForReading

        guard !text.isEmpty else {
            throw ImportError.noReadableText
        }

        return importedBook(title: title, pages: paginate(text), format: .text)
    }

    private static func importedBook(title: String, pages: [String], format: BookFormat) -> Book {
        Book(
            title: title,
            author: "Imported Book",
            coverSymbol: "doc.text.fill",
            coverColorName: "orange",
            pages: pages,
            format: format
        )
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
