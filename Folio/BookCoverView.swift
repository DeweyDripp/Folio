import SwiftUI

struct BookCoverView: View {
    let book: Book

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
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var coverArtwork: some View {
        if let data = book.coverData, let image = UIImage(data: data) {
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

    private var coverColor: Color {
        switch book.coverColorName {
        case "indigo": .indigo
        case "orange": .orange
        default: .teal
        }
    }
}
