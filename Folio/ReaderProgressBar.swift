import SwiftUI

/// A quiet, always-readable progress indicator at the bottom of the reader.
struct ReaderProgressBar: View {
    let title: String
    let fraction: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .lineLimit(1)

            ProgressView(value: safeFraction)
                .frame(maxWidth: .infinity)

            Text("\(Int((safeFraction * 100).rounded()))%")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) progress")
        .accessibilityValue("\(Int((safeFraction * 100).rounded())) percent")
    }

    private var safeFraction: Double {
        min(1, max(0, fraction))
    }
}
