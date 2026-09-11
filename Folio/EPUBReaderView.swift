import Combine
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

struct EPUBReaderView: View {
    @StateObject private var model: EPUBReaderModel
    @StateObject private var bookmarks: ReaderBookmarkStore
    @ObservedObject var settings: ReaderSettings
    @Binding var showsMenu: Bool

    init(book: Book, settings: ReaderSettings, showsMenu: Binding<Bool>) {
        self.settings = settings
        _showsMenu = showsMenu
        _model = StateObject(wrappedValue: EPUBReaderModel(book: book, settings: settings))
        _bookmarks = StateObject(wrappedValue: ReaderBookmarkStore(bookID: book.id))
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
        .overlay(alignment: .top) {
            if showsMenu {
                ReaderMenuBar(
                    settings: settings,
                    bookmarks: bookmarks,
                    supportsPublisherStyles: true,
                    chapters: model.chapters,
                    isCurrentLocationBookmarked: isCurrentLocationBookmarked,
                    selectChapter: { chapter in
                        Task {
                            await model.go(toChapter: chapter.id)
                        }
                        closeMenu()
                    },
                    selectBookmark: { bookmark in
                        Task {
                            await model.go(to: bookmark)
                        }
                        closeMenu()
                    },
                    toggleCurrentBookmark: toggleCurrentBookmark,
                    dismiss: closeMenu
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .preferredColorScheme(settings.theme == .dark ? .dark : .light)
        .task {
            await model.load()
        }
    }

    private var isCurrentLocationBookmarked: Bool {
        guard let json = model.currentLocationJSON else { return false }
        return bookmarks.containsLocation(json)
    }

    private func toggleCurrentBookmark() {
        guard let json = model.currentLocationJSON else { return }
        bookmarks.toggleLocation(json: json, title: model.currentLocationTitle)
    }

    private func closeMenu() {
        withAnimation(.snappy) {
            showsMenu = false
        }
    }
}

@MainActor
final class EPUBReaderModel: NSObject, ObservableObject, EPUBNavigatorDelegate {
    @Published private(set) var navigator: EPUBNavigatorViewController?
    @Published private(set) var errorMessage: String?
    @Published private(set) var chapters: [ReaderChapter] = []
    @Published private(set) var currentLocationJSON: String?
    @Published private(set) var currentLocationTitle = "Current location"

    private let book: Book
    private let settings: ReaderSettings
    private var isLoading = false
    private var chapterLinks: [String: ReadiumShared.Link] = [:]

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
            let tableOfContents = (try? await publication.tableOfContents().get()) ?? []
            prepareChapters(from: tableOfContents)
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
            updateCurrentLocation(initialLocation ?? navigator.currentLocation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        EPUBProgressStore.save(locator, for: book.id)
        updateCurrentLocation(locator)
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        errorMessage = "The reader encountered an error."
    }

    func go(toChapter chapterID: String) async {
        guard let navigator, let link = chapterLinks[chapterID] else { return }
        await navigator.go(to: link, options: .animated)
    }

    func go(to bookmark: ReaderBookmark) async {
        guard let navigator,
              let json = bookmark.locationJSON,
              let locator = try? Locator(jsonString: json)
        else {
            return
        }

        await navigator.go(to: locator, options: .animated)
    }

    private func prepareChapters(from links: [ReadiumShared.Link]) {
        var newChapters: [ReaderChapter] = []
        var newChapterLinks: [String: ReadiumShared.Link] = [:]
        var nextID = 0

        func add(_ links: [ReadiumShared.Link], depth: Int) {
            for link in links {
                let id = String(nextID)
                nextID += 1

                if let title = link.title, !title.isEmpty {
                    newChapters.append(ReaderChapter(id: id, title: title, depth: depth))
                    newChapterLinks[id] = link
                }

                add(link.children, depth: depth + 1)
            }
        }

        add(links, depth: 0)
        chapters = newChapters
        chapterLinks = newChapterLinks
    }

    private func updateCurrentLocation(_ locator: Locator?) {
        guard let locator else { return }
        currentLocationJSON = try? locator.jsonString()

        if let title = locator.title, !title.isEmpty {
            currentLocationTitle = title
        } else if let position = locator.locations.position {
            currentLocationTitle = "Position \(position)"
        } else if let progression = locator.locations.totalProgression {
            currentLocationTitle = "\(Int(progression * 100))%"
        } else {
            currentLocationTitle = "Saved location"
        }
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

enum EPUBProgressStore {
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

    static func remove(for bookID: UUID) {
        UserDefaults.standard.removeObject(forKey: keyPrefix + bookID.uuidString)
    }
}
