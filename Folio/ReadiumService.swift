import Foundation
import ReadiumShared
import ReadiumStreamer

@MainActor
final class ReadiumService {
    static let shared = ReadiumService()

    private let assetRetriever: AssetRetriever
    private let publicationOpener: PublicationOpener

    private init() {
        let httpClient = DefaultHTTPClient()
        assetRetriever = AssetRetriever(httpClient: httpClient)
        publicationOpener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: httpClient,
                assetRetriever: assetRetriever,
                pdfFactory: DefaultPDFDocumentFactory()
            )
        )
    }

    func openPublication(at url: URL) async throws -> Publication {
        guard let fileURL = url.fileURL else {
            throw ReadiumServiceError.invalidURL
        }

        let asset = try await assetRetriever.retrieve(url: fileURL).get()
        return try await publicationOpener
            .open(asset: asset, allowUserInteraction: true)
            .get()
    }
}

private enum ReadiumServiceError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        "Folio couldn’t locate this EPUB file."
    }
}
