import Combine
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

struct EPUBReaderView: View {
    @StateObject private var model: EPUBReaderModel
    @StateObject private var bookmarks: ReaderBookmarkStore
    @StateObject private var highlights: ReaderHighlightStore
    @ObservedObject var settings: ReaderSettings
    @Binding var showsMenu: Bool
    @State private var editingHighlight: ReaderHighlight?

    init(book: Book, settings: ReaderSettings, showsMenu: Binding<Bool>) {
        self.settings = settings
        _showsMenu = showsMenu
        _model = StateObject(wrappedValue: EPUBReaderModel(book: book, settings: settings))
        _bookmarks = StateObject(wrappedValue: ReaderBookmarkStore(bookID: book.id))
        _highlights = StateObject(wrappedValue: ReaderHighlightStore(bookID: book.id))
    }

    var body: some View {
        Group {
            if let navigator = model.navigator {
                GeometryReader { geometry in
                    EPUBNavigatorContainer(
                        navigator: navigator,
                        settings: settings,
                        availableWidth: geometry.size.width,
                        onHighlightSelection: addHighlight
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
                    highlights: highlights,
                    supportsPublisherStyles: true,
                    supportsHighlights: true,
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
                    selectHighlight: { highlight in
                        Task {
                            await model.go(to: highlight)
                        }
                        closeMenu()
                    },
                    editHighlight: { highlight in
                        editingHighlight = highlight
                    },
                    dismiss: closeMenu
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !showsMenu, model.currentLocationJSON != nil {
                BookmarkRibbon(
                    isBookmarked: isCurrentLocationBookmarked,
                    toggle: toggleCurrentBookmark
                )
            }
        }
        .preferredColorScheme(settings.theme == .dark ? .dark : .light)
        .sheet(item: $editingHighlight) { highlight in
            HighlightNoteEditor(highlight: highlight) { note, color in
                highlights.update(highlight, note: note, color: color)
            }
        }
        .onReceive(highlights.$highlights) { savedHighlights in
            model.applyHighlights(savedHighlights)
        }
        .task {
            model.onHighlightActivated = { highlightID in
                editingHighlight = highlights.highlights.first { $0.id.uuidString == highlightID }
            }
            await model.load()
            model.applyHighlights(highlights.highlights)
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

    private func addHighlight(_ locator: Locator) {
        guard let json = try? locator.jsonString() else { return }
        let selectedText = locator.text.highlight?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayText = selectedText.flatMap { $0.isEmpty ? nil : $0 } ?? "Highlighted text"
        highlights.add(
            locatorJSON: json,
            text: displayText,
            progression: locator.locations.totalProgression
        )
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
    private let highlightDecorationGroup = "highlights"
    var onHighlightActivated: ((String) -> Void)?

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
                fontFamily: settings.readiumFont,
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
                config: EPUBNavigatorViewController.Configuration(
                    preferences: preferences,
                    editingActions: EditingAction.defaultActions + [
                        EditingAction(
                            title: "Highlight",
                            action: #selector(EPUBHostViewController.highlightSelection)
                        )
                    ],
                    fontFamilyDeclarations: CustomFontStore.shared.readiumDeclarations
                )
            )
            navigator.delegate = self
            navigator.observeDecorationInteractions(inGroup: highlightDecorationGroup) { [weak self] event in
                self?.onHighlightActivated?(event.decoration.id)
            }
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
        _ = await navigator.go(to: link, options: pageTurnOptions)
    }

    func go(to bookmark: ReaderBookmark) async {
        guard let navigator,
              let json = bookmark.locationJSON,
              let locator = try? Locator(jsonString: json)
        else {
            return
        }

        _ = await navigator.go(to: locator, options: pageTurnOptions)
    }

    func go(to highlight: ReaderHighlight) async {
        guard let navigator,
              let locator = try? Locator(jsonString: highlight.locatorJSON)
        else {
            return
        }
        _ = await navigator.go(to: locator, options: pageTurnOptions)
    }

    func applyHighlights(_ highlights: [ReaderHighlight]) {
        guard let navigator else { return }

        let decorations = highlights.compactMap { highlight -> Decoration? in
            guard let locator = try? Locator(jsonString: highlight.locatorJSON) else { return nil }
            return Decoration(
                id: highlight.id.uuidString,
                locator: locator,
                style: .highlight(tint: highlight.color.uiColor)
            )
        }
        navigator.apply(decorations: decorations, in: highlightDecorationGroup)
    }

    private var pageTurnOptions: NavigatorGoOptions {
        NavigatorGoOptions(animated: settings.usesPageTurnAnimation)
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
    let onHighlightSelection: (Locator) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> EPUBHostViewController {
        EPUBHostViewController(
            navigator: navigator,
            onHighlightSelection: onHighlightSelection,
            usesPageTurnAnimation: settings.usesPageTurnAnimation
        )
    }

    func updateUIViewController(_ viewController: EPUBHostViewController, context: Context) {
        viewController.onHighlightSelection = onHighlightSelection
        viewController.usesPageTurnAnimation = settings.usesPageTurnAnimation
        viewController.paperColor = UIColor(settings.theme.backgroundColor)
        let showsTwoPages = settings.pageLayout.showsTwoPages(for: availableWidth)
        let signature = [
            String(showsTwoPages),
            settings.theme.rawValue,
            settings.fontIdentifier,
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
                fontFamily: settings.readiumFont,
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

private extension ReaderSettings {
    var readiumFont: ReadiumNavigator.FontFamily {
        if let customFontName {
            return ReadiumNavigator.FontFamily(rawValue: customFontName)
        }

        return switch font {
        case .serif: ReadiumNavigator.FontFamily.serif
        case .sansSerif: ReadiumNavigator.FontFamily.sansSerif
        case .athelas: ReadiumNavigator.FontFamily.athelas
        case .openDyslexic: ReadiumNavigator.FontFamily.openDyslexic
        }
    }
}

private final class EPUBHostViewController: PaperTurnController {
    private let navigator: EPUBNavigatorViewController
    var onHighlightSelection: (Locator) -> Void

    init(
        navigator: EPUBNavigatorViewController,
        onHighlightSelection: @escaping (Locator) -> Void,
        usesPageTurnAnimation: Bool
    ) {
        self.navigator = navigator
        self.onHighlightSelection = onHighlightSelection
        super.init(nibName: nil, bundle: nil)
        self.usesPageTurnAnimation = usesPageTurnAnimation
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

        view.accessibilityIdentifier = "epub.reader"

        canTurnPage = { [weak navigator] in navigator?.currentSelection == nil }
        prepareTurn = { [weak navigator] left in
            guard let navigator, let original = navigator.currentLocation else { return nil }
            let forward = left == (navigator.publication.metadata.readingProgression != .rtl)
            let moved = forward
                ? await navigator.goForward(options: NavigatorGoOptions(animated: false))
                : await navigator.goBackward(options: NavigatorGoOptions(animated: false))
            guard moved else { return nil }
            return { _ = await navigator.go(to: original, options: NavigatorGoOptions(animated: false)) }
        }
        navigator.addObserver(.tap { [weak self] event in
            guard let self, self.navigator.currentSelection == nil else { return false }
            let width = self.view.bounds.width
            if event.location.x < width * 0.2 {
                self.turnByTap(left: false)
                return true
            }
            if event.location.x > width * 0.8 {
                self.turnByTap(left: true)
                return true
            }
            return false
        })
    }

    @objc func highlightSelection() {
        guard let selection = navigator.currentSelection else { return }
        onHighlightSelection(selection.locator)
        navigator.clearSelection()
    }
}

private extension ReaderHighlightColor {
    var uiColor: UIColor {
        switch self {
        case .yellow: UIColor(red: 1, green: 0.82, blue: 0.2, alpha: 1)
        case .pink: UIColor(red: 1, green: 0.48, blue: 0.62, alpha: 1)
        case .green: UIColor(red: 0.42, green: 0.82, blue: 0.48, alpha: 1)
        case .blue: UIColor(red: 0.35, green: 0.66, blue: 1, alpha: 1)
        }
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
