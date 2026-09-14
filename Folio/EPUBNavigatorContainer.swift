import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

/// Bridges Readium's UIKit navigator into Folio's SwiftUI reader.
struct EPUBNavigatorContainer: UIViewControllerRepresentable {
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
