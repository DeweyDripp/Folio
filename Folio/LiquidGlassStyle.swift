import SwiftUI

extension View {
    @ViewBuilder
    func folioControlPanel(cornerRadius: CGFloat = 18) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
        } else {
            self
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
        }
    }
}
