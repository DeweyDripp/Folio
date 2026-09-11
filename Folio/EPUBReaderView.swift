import Combine
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

struct EPUBReaderView: View {
    @StateObject private var model: EPUBReaderModel
    @ObservedObject var settings: ReaderSettings

    init(book: Book, settings: ReaderSettings) {
        self.settings = settings
        _model = StateObject(wrappedValue: EPUBReaderModel(book: book, settings: settings))
    }

    var body: some View {
        Group {
            if let navigator = model.navigator {
                GeometryReader { geometry in
                    EPUBNavigatorContainer(
                        navigator: navigator,
                        settings: settings,
                        availableWidth: geometry.size.width
                    )
                }
            } else if let errorMessage = model.errorMessage {
                ContentUnavailableView(
                    "Couldn’t Open Book",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView("Opening book…")
            }
        }
        .preferredColorScheme(settings.theme == .dark ? .dark : .light)
        .task {
            await model.load()
        }
    }
}

@MainActor
final class EPUBReaderModel: NSObject, ObservableObject, EPUBNavigatorDelegate {
    @Published private(set) var navigator: EPUBNavigatorViewController?
    @Published private(set) var errorMessage: String?

    private let book: Book
    private let settings: ReaderSettings
    private var isLoading = false

    init(book: Book, settings: ReaderSettings) {
        self.book = book
        self.settings = settings
    }

    func load() async {
        guard navigator == nil, !isLoading else { return }
        isLoading = true

        do {
            guard let fileName = book.fileName else {
                throw EPUBReaderError.missingFile
            }

            let fileURL = ImportedBookStore.booksDirectory.appending(path: fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw EPUBReaderError.missingFile
            }

            let publication = try await ReadiumService.shared.openPublication(at: fileURL)
            let initialLocation = EPUBProgressStore.load(for: book.id)
            let preferences = EPUBPreferences(
                columnCount: .auto,
                fontFamily: settings.font.readiumFont,
                fontSize: settings.fontScale,
                lineHeight: settings.lineHeight,
                pageMargins: settings.pageMargins,
                publisherStyles: settings.usesPublisherStyles,
                spread: .auto,
                theme: settings.theme.readiumTheme
            )

            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initialLocation,
                config: EPUBNavigatorViewController.Configuration(preferences: preferences)
            )
            navigator.delegate = self
            self.navigator = navigator
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        EPUBProgressStore.save(locator, for: book.id)
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        errorMessage = "The reader encountered an error."
    }

}

private struct EPUBNavigatorContainer: UIViewControllerRepresentable {
    let navigator: EPUBNavigatorViewController
    @ObservedObject var settings: ReaderSettings
    let availableWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> EPUBHostViewController {
        EPUBHostViewController(navigator: navigator)
    }

    func updateUIViewController(_ viewController: EPUBHostViewController, context: Context) {
        let showsTwoPages = settings.pageLayout.showsTwoPages(for: availableWidth)
        let signature = [
            String(showsTwoPages),
            settings.theme.rawValue,
            settings.font.rawValue,
            String(settings.fontScale),
            String(settings.lineHeight),
            String(settings.pageMargins),
            String(settings.usesPublisherStyles)
        ].joined(separator: "|")

        guard context.coordinator.settingsSignature != signature else { return }
        context.coordinator.settingsSignature = signature

        navigator.submitPreferences(
            EPUBPreferences(
                columnCount: showsTwoPages ? .two : .one,
                fontFamily: settings.font.readiumFont,
                fontSize: settings.fontScale,
                lineHeight: settings.lineHeight,
                pageMargins: settings.pageMargins,
                publisherStyles: settings.usesPublisherStyles,
                spread: showsTwoPages ? .always : .never,
                theme: settings.theme.readiumTheme
            )
        )
    }

    final class Coordinator {
        var settingsSignature: String?
    }
}

private extension ReaderTheme {
    var readiumTheme: ReadiumNavigator.Theme {
        switch self {
        case .light: .light
        case .sepia: .sepia
        case .dark: .dark
        }
    }
}

private extension ReaderFont {
    var readiumFont: ReadiumNavigator.FontFamily {
        switch self {
        case .serif: .serif
        case .sansSerif: .sansSerif
        case .athelas: .athelas
        case .openDyslexic: .openDyslexic
        }
    }
}

private final class EPUBHostViewController: UIViewController {
    private let navigator: EPUBNavigatorViewController

    init(navigator: EPUBNavigatorViewController) {
        self.navigator = navigator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(navigator)
        navigator.view.frame = view.bounds
        navigator.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(navigator.view)
        navigator.didMove(toParent: self)
    }
}

private enum EPUBReaderError: LocalizedError {
    case missingFile

    var errorDescription: String? {
        "The EPUB file is missing from Folio’s library. Try importing it again."
    }
}

private enum EPUBProgressStore {
    private static let keyPrefix = "epub-location-"

    static func load(for bookID: UUID) -> Locator? {
        guard let json = UserDefaults.standard.string(forKey: keyPrefix + bookID.uuidString) else {
            return nil
        }

        return try? Locator(jsonString: json)
    }

    static func save(_ locator: Locator, for bookID: UUID) {
        guard let json = try? locator.jsonString() else { return }
        UserDefaults.standard.set(json, forKey: keyPrefix + bookID.uuidString)
    }
}
