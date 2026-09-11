import Combine
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

struct EPUBReaderView: View {
    @StateObject private var model: EPUBReaderModel

    init(book: Book) {
        _model = StateObject(wrappedValue: EPUBReaderModel(book: book))
    }

    var body: some View {
        Group {
            if let navigator = model.navigator {
                GeometryReader { geometry in
                    EPUBNavigatorContainer(
                        navigator: navigator,
                        showsTwoPages: geometry.size.width >= 700
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
    private var isLoading = false

    init(book: Book) {
        self.book = book
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
                pageMargins: 1,
                publisherStyles: true,
                spread: .auto
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
    let showsTwoPages: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> EPUBHostViewController {
        EPUBHostViewController(navigator: navigator)
    }

    func updateUIViewController(_ viewController: EPUBHostViewController, context: Context) {
        guard context.coordinator.showsTwoPages != showsTwoPages else { return }
        context.coordinator.showsTwoPages = showsTwoPages

        navigator.submitPreferences(
            EPUBPreferences(
                columnCount: showsTwoPages ? .two : .one,
                spread: showsTwoPages ? .always : .never
            )
        )
    }

    final class Coordinator {
        var showsTwoPages: Bool?
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
