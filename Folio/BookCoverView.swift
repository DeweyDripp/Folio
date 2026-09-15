import SwiftUI

struct BookCoverView: View {
    let book: Book
    let progress: ReadingProgress?

    init(book: Book, progress: ReadingProgress? = nil) {
        self.book = book
        self.progress = progress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 14)
                .fill(coverColor.gradient)
                .aspectRatio(0.68, contentMode: .fit)
                .overlay {
                coverArtwork
                }
                .shadow(color: .black.opacity(0.18), radius: 8, y: 5)

            Text(book.title)
                .font(.headline)
                .lineLimit(1)

            Text(book.author)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let progress, progress.fraction > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress.fraction)
                    Text(progressLabel(progress.fraction))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var coverArtwork: some View {
        if let image = ImportedBookStore.coverImage(for: book) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            VStack(spacing: 16) {
                Image(systemName: book.coverSymbol)
                    .font(.system(size: 42))

                Text(book.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .foregroundStyle(.white)
            .padding()
        }
    }

    private func progressLabel(_ fraction: Double) -> String {
        if fraction >= 0.995 { return "Finished" }
        return "\(Int((fraction * 100).rounded()))% read"
    }

    private var coverColor: Color {
        switch book.coverColorName {
        case "indigo": .indigo
        case "orange": .orange
        default: .teal
        }
    }
}
