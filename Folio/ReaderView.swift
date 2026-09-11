import SwiftUI

struct ReaderView: View {
    let book: Book

    var body: some View {
        Group {
            if book.bookFormat == .epub {
                EPUBReaderView(book: book)
            } else {
                PagedReaderView(book: book)
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PagedReaderView: View {
    let book: Book

    @State private var currentPage = 0

    var body: some View {
        GeometryReader { geometry in
            let showsTwoPages = geometry.size.width >= 700
            let pageStep = showsTwoPages ? 2 : 1

            VStack(spacing: 0) {
                readerPages(showsTwoPages: showsTwoPages)

                Divider()

                readerControls(pageStep: pageStep)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.bar)
            }
            .onChange(of: showsTwoPages) { _, isWide in
                if isWide {
                    currentPage -= currentPage % 2
                }
            }
        }
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private func readerPages(showsTwoPages: Bool) -> some View {
        if showsTwoPages {
            HStack(spacing: 1) {
                PageView(text: book.pages[currentPage])

                if currentPage + 1 < book.pages.count {
                    PageView(text: book.pages[currentPage + 1])
                } else {
                    Color(.systemBackground)
                }
            }
            .background(Color(.separator))
        } else {
            PageView(text: book.pages[currentPage])
        }
    }

    private func readerControls(pageStep: Int) -> some View {
        HStack {
            Button {
                currentPage = max(0, currentPage - pageStep)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(currentPage == 0)

            Spacer()

            Text(pageLabel(pageStep: pageStep))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                currentPage = min(book.pages.count - 1, currentPage + pageStep)
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(currentPage + pageStep >= book.pages.count)
        }
        .buttonStyle(.bordered)
    }

    private func pageLabel(pageStep: Int) -> String {
        if pageStep == 2, currentPage + 1 < book.pages.count {
            return "Pages \(currentPage + 1)–\(currentPage + 2) of \(book.pages.count)"
        }

        return "Page \(currentPage + 1) of \(book.pages.count)"
    }
}

private struct PageView: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.title3, design: .serif))
                .lineSpacing(8)
                .frame(maxWidth: 620, alignment: .topLeading)
                .padding(.horizontal, 32)
                .padding(.vertical, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview("Narrow") {
    NavigationStack {
        ReaderView(book: sampleBooks[0])
    }
}
