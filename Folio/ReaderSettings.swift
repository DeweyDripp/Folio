import Combine
import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case light
    case sepia
    case dark

    var id: Self { self }

    var title: String { rawValue.capitalized }

    var backgroundColor: Color {
        switch self {
        case .light: .white
        case .sepia: Color(red: 0.98, green: 0.95, blue: 0.87)
        case .dark: Color(red: 0.08, green: 0.08, blue: 0.09)
        }
    }

    var textColor: Color {
        self == .dark ? Color(white: 0.92) : Color(white: 0.12)
    }
}

enum ReaderFont: String, CaseIterable, Identifiable {
    case serif
    case sansSerif
    case athelas
    case openDyslexic

    var id: Self { self }

    var title: String {
        switch self {
        case .serif: "Serif"
        case .sansSerif: "Sans Serif"
        case .athelas: "Athelas"
        case .openDyslexic: "OpenDyslexic"
        }
    }

    func swiftUIFont(size: CGFloat) -> Font {
        switch self {
        case .serif:
            .system(size: size, design: .serif)
        case .sansSerif:
            .system(size: size, design: .default)
        case .athelas:
            .custom("Athelas", size: size)
        case .openDyslexic:
            .system(size: size, design: .rounded)
        }
    }
}

enum ReaderPageLayout: String, CaseIterable, Identifiable {
    case automatic
    case single
    case double

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Auto"
        case .single: "One"
        case .double: "Two"
        }
    }

    func showsTwoPages(for width: CGFloat) -> Bool {
        switch self {
        case .automatic: width >= 700
        case .single: false
        case .double: true
        }
    }
}

@MainActor
final class ReaderSettings: ObservableObject {
    @Published var theme: ReaderTheme { didSet { save() } }
    @Published var font: ReaderFont { didSet { save() } }
    @Published var customFontName: String? { didSet { save() } }
    @Published var fontScale: Double { didSet { save() } }
    @Published var lineHeight: Double { didSet { save() } }
    @Published var pageMargins: Double { didSet { save() } }
    @Published var pageLayout: ReaderPageLayout { didSet { save() } }
    @Published var usesPageTurnAnimation: Bool { didSet { save() } }
    @Published var usesPublisherStyles: Bool { didSet { save() } }

    private let defaults = UserDefaults.standard

    init() {
        theme = ReaderTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .light
        font = ReaderFont(rawValue: defaults.string(forKey: Key.font) ?? "") ?? .serif
        customFontName = defaults.string(forKey: Key.customFontName)
        fontScale = defaults.object(forKey: Key.fontScale) as? Double ?? 1
        lineHeight = defaults.object(forKey: Key.lineHeight) as? Double ?? 1.4
        pageMargins = defaults.object(forKey: Key.pageMargins) as? Double ?? 1
        pageLayout = ReaderPageLayout(rawValue: defaults.string(forKey: Key.pageLayout) ?? "") ?? .automatic
        usesPageTurnAnimation = defaults.object(forKey: Key.pageTurnAnimation) as? Bool ?? true
        usesPublisherStyles = defaults.object(forKey: Key.publisherStyles) as? Bool ?? true
    }

    func reset() {
        theme = .light
        font = .serif
        customFontName = nil
        fontScale = 1
        lineHeight = 1.4
        pageMargins = 1
        pageLayout = .automatic
        usesPageTurnAnimation = true
        usesPublisherStyles = true
    }

    private func save() {
        defaults.set(theme.rawValue, forKey: Key.theme)
        defaults.set(font.rawValue, forKey: Key.font)
        defaults.set(customFontName, forKey: Key.customFontName)
        defaults.set(fontScale, forKey: Key.fontScale)
        defaults.set(lineHeight, forKey: Key.lineHeight)
        defaults.set(pageMargins, forKey: Key.pageMargins)
        defaults.set(pageLayout.rawValue, forKey: Key.pageLayout)
        defaults.set(usesPageTurnAnimation, forKey: Key.pageTurnAnimation)
        defaults.set(usesPublisherStyles, forKey: Key.publisherStyles)
    }

    private enum Key {
        static let theme = "reader-theme"
        static let font = "reader-font"
        static let customFontName = "reader-custom-font-name"
        static let fontScale = "reader-font-scale"
        static let lineHeight = "reader-line-height"
        static let pageMargins = "reader-page-margins"
        static let pageLayout = "reader-page-layout"
        static let pageTurnAnimation = "reader-page-turn-animation"
        static let publisherStyles = "reader-publisher-styles"
    }

    var fontIdentifier: String {
        get { customFontName ?? font.rawValue }
        set {
            if let builtInFont = ReaderFont(rawValue: newValue) {
                customFontName = nil
                font = builtInFont
            } else {
                customFontName = newValue
            }
        }
    }

    func swiftUIFont(size: CGFloat) -> Font {
        if let customFontName {
            return .custom(customFontName, size: size)
        }
        return font.swiftUIFont(size: size)
    }
}
