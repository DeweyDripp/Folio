import Combine
import ReadiumNavigator
import ReadiumShared
import SwiftUI

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if settings.progressDisplay != .hidden, model.navigator != nil {
                ReaderProgressBar(
                    title: settings.progressDisplay == .chapter
                        ? model.currentLocationTitle
                        : "Book",
                    fraction: settings.progressDisplay == .chapter
                        ? model.currentChapterProgress
                        : model.currentProgress
                )
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
                    currentLocationTitle: model.currentLocationTitle,
                    progressFraction: model.currentProgress,
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
    @Published private(set) var currentProgress = 0.0
    @Published private(set) var currentChapterProgress = 0.0

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
        currentProgress = min(1, max(0, locator.locations.totalProgression ?? currentProgress))
        currentChapterProgress = min(1, max(0, locator.locations.progression ?? currentChapterProgress))

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

private enum EPUBReaderError: LocalizedError {
    case missingFile

    var errorDescription: String? {
        "The EPUB file is missing from Folio’s library. Try importing it again."
    }
}

@MainActor
enum EPUBProgressStore {
    private static let keyPrefix = "epub-location-"

    static func load(for bookID: UUID) -> Locator? {
        if let json = ReadingProgressStore.shared.progress(for: bookID)?.locatorJSON {
            return try? Locator(jsonString: json)
        }

        // Migrate progress written by the first Folio EPUB reader.
        let legacyKey = keyPrefix + bookID.uuidString
        guard let json = UserDefaults.standard.string(forKey: legacyKey),
              let locator = try? Locator(jsonString: json)
        else {
            return nil
        }
        save(locator, for: bookID)
        UserDefaults.standard.removeObject(forKey: legacyKey)
        return locator
    }

    static func save(_ locator: Locator, for bookID: UUID) {
        guard let json = try? locator.jsonString() else { return }
        ReadingProgressStore.shared.saveEPUB(
            locatorJSON: json,
            fraction: locator.locations.totalProgression,
            chapterTitle: locator.title,
            for: bookID
        )
    }

    static func removeLegacyProgress(for bookID: UUID) {
        UserDefaults.standard.removeObject(forKey: keyPrefix + bookID.uuidString)
    }
}
