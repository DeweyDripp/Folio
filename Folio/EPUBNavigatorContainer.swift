import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

/// Bridges Readium's UIKit navigator into Folio's SwiftUI reader.
struct EPUBNavigatorContainer: UIViewControllerRepresentable {
    let navigator: EPUBNavigatorViewController
    @ObservedObject var settings: ReaderSettings
    let layout: ReaderLayout
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
        let showsTwoPages = layout.showsTwoPages
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
                // Readium advances by exactly one viewport width per turn.
                // A custom CSS column gap would accumulate as horizontal drift.
                columnGap: 0,
                fontFamily: settings.readiumFont,
                fontSize: settings.fontScale,
                lineHeight: settings.lineHeight,
                pageMargins: settings.pageMargins,
                publisherStyles: settings.usesPublisherStyles,
                scroll: false,
                spread: showsTwoPages ? .always : .never,
                theme: settings.theme.readiumTheme
            )
        )
    }

    final class Coordinator {
        var settingsSignature: String?
    }
}

extension ReaderTheme {
    var readiumTheme: ReadiumNavigator.Theme {
        switch self {
        case .light: .light
        case .sepia: .sepia
        case .dark: .dark
        }
    }
}

extension ReaderSettings {
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

final class EPUBHostViewController: PaperTurnController {
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

        canTurnPage = { [weak navigator] in navigator?.currentSelection == nil }
        prepareTurn = { [weak self] left in
            guard let self, let original = navigator.currentLocation else { return nil }
            let forward = left == (navigator.publication.metadata.readingProgression != .rtl)
            guard await self.moveByPageOrChapter(forward: forward) else { return nil }
            return { [weak self] in
                guard let self else { return }
                _ = await self.navigator.go(to: original, options: NavigatorGoOptions(animated: false))
            }
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

    private func moveByPageOrChapter(forward: Bool) async -> Bool {
        let options = NavigatorGoOptions(animated: false)
        let movedWithinChapter = forward
            ? await navigator.goForward(options: options)
            : await navigator.goBackward(options: options)

        if movedWithinChapter {
            return true
        }

        return await moveToAdjacentChapter(forward: forward, options: options)
    }

    private func moveToAdjacentChapter(forward: Bool, options: NavigatorGoOptions) async -> Bool {
        guard
            let currentLocation = navigator.currentLocation,
            let currentIndex = navigator.publication.readingOrder.firstIndexWithHREF(currentLocation.href)
        else {
            return false
        }

        let adjacentIndex = forward ? currentIndex + 1 : currentIndex - 1
        guard navigator.publication.readingOrder.indices.contains(adjacentIndex) else {
            return false
        }

        let adjacentLink = navigator.publication.readingOrder[adjacentIndex]
        let progression = forward ? 0.0 : 1.0
        let locator = Locator(
            href: adjacentLink.url(),
            mediaType: adjacentLink.mediaType ?? currentLocation.mediaType,
            title: adjacentLink.title,
            locations: Locator.Locations(progression: progression)
        )
        return await navigator.go(to: locator, options: options)
    }

    @objc func highlightSelection() {
        guard let selection = navigator.currentSelection else { return }
        onHighlightSelection(selection.locator)
        navigator.clearSelection()
    }
}

extension ReaderHighlightColor {
    var uiColor: UIColor {
        switch self {
        case .yellow: UIColor(red: 1, green: 0.82, blue: 0.2, alpha: 1)
        case .pink: UIColor(red: 1, green: 0.48, blue: 0.62, alpha: 1)
        case .green: UIColor(red: 0.42, green: 0.82, blue: 0.48, alpha: 1)
        case .blue: UIColor(red: 0.35, green: 0.66, blue: 1, alpha: 1)
        }
    }
}
