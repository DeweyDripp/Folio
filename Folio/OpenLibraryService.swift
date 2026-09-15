import Foundation

struct OpenLibraryMetadata: Identifiable {
    let id = UUID()
    let title: String?
    let author: String?
    let publisher: String?
    let publishYear: Int?
    let language: String?
    let isbn: String?
}

enum OpenLibraryService {
    private static let endpoint = URL(string: "https://openlibrary.org/search.json")!

    static func search(title: String, author: String, isbn: String) async throws -> [OpenLibraryMetadata] {
        let cleanISBN = isbn.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanISBN.isEmpty || !cleanTitle.isEmpty else { return [] }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        let query: String
        if !cleanISBN.isEmpty {
            query = "isbn:\(cleanISBN)"
        } else if !cleanAuthor.isEmpty {
            query = "title:\(cleanTitle) author:\(cleanAuthor)"
        } else {
            query = cleanTitle
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(
                name: "fields",
                value: "title,author_name,publisher,first_publish_year,language,isbn"
            )
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw LookupError.badResponse
        }

        let result = try JSONDecoder().decode(SearchResponse.self, from: data)
        return result.docs.map { match in
            OpenLibraryMetadata(
                title: match.title,
                author: match.authorNames?.first,
                publisher: match.publishers?.first,
                publishYear: match.firstPublishYear,
                language: match.languages?.first.map(languageName),
                isbn: preferredISBN(from: match.isbns)
            )
        }
    }

    private static func preferredISBN(from values: [String]?) -> String? {
        guard let values else { return nil }
        return values.first(where: { $0.count == 13 }) ?? values.first
    }

    private static func languageName(_ code: String) -> String {
        switch code.lowercased() {
        case "eng": "English"
        case "spa": "Spanish"
        case "fre", "fra": "French"
        case "ger", "deu": "German"
        case "ita": "Italian"
        case "por": "Portuguese"
        case "jpn": "Japanese"
        case "zho": "Chinese"
        default: code.uppercased()
        }
    }

    private struct SearchResponse: Decodable {
        let docs: [SearchDocument]
    }

    private struct SearchDocument: Decodable {
        let title: String?
        let authorNames: [String]?
        let publishers: [String]?
        let firstPublishYear: Int?
        let languages: [String]?
        let isbns: [String]?

        enum CodingKeys: String, CodingKey {
            case title
            case authorNames = "author_name"
            case publishers = "publisher"
            case firstPublishYear = "first_publish_year"
            case languages = "language"
            case isbns = "isbn"
        }
    }

    private enum LookupError: LocalizedError {
        case badResponse

        var errorDescription: String? {
            "Open Library returned an unavailable response."
        }
    }
}
