import SwiftUI

struct BookmarkRibbon: View {
    let isBookmarked: Bool
    let toggle: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .contentShape(Rectangle())

            if isBookmarked {
                ribbon
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: 68, height: 86)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.45) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                toggle()
            }
        }
        .sensoryFeedback(.success, trigger: isBookmarked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Add bookmark")
        .accessibilityHint("Press and hold the top-right corner")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(
            named: Text(isBookmarked ? "Remove bookmark" : "Add bookmark"),
            toggle
        )
    }

    private var ribbon: some View {
        Image(systemName: "bookmark.fill")
            .font(.system(size: 34))
            .foregroundStyle(.red)
            .symbolRenderingMode(.monochrome)
            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
            .padding(.trailing, 10)
            .offset(y: -3)
    }
}
