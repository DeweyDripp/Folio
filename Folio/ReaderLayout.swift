import SwiftUI

/// Layout information shared by the built-in and EPUB readers.
/// It is derived from the space the view receives, rather than the device model.
struct ReaderLayout: Equatable {
    let showsTwoPages: Bool
    let gutterWidth: CGFloat

    static func resolve(
        pageLayout: ReaderPageLayout,
        horizontalSizeClass: UserInterfaceSizeClass?,
        geometry: GeometryProxy
    ) -> ReaderLayout {
        let hasRegularWidth = horizontalSizeClass == .regular
        let availableContentWidth = geometry.size.width
            - geometry.safeAreaInsets.leading
            - geometry.safeAreaInsets.trailing
        let hasSpreadWidth = availableContentWidth >= 700
        let automaticSpread = hasRegularWidth && hasSpreadWidth
        let showsTwoPages: Bool

        switch pageLayout {
        case .automatic, .double:
            showsTwoPages = automaticSpread
        case .single:
            showsTwoPages = false
        }

        // Scale the gap with the local view instead of assuming a Duo-specific width.
        let gutterWidth = showsTwoPages
            ? min(32, max(16, availableContentWidth * 0.02))
            : 0

        return ReaderLayout(showsTwoPages: showsTwoPages, gutterWidth: gutterWidth)
    }
}
