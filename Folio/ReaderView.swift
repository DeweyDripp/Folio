import SwiftUI

struct ReaderView: View {
    let book: Book
    @StateObject private var settings = ReaderSettings()
    @State private var showsSettings = false

    var body: some View {
        Group {
            if book.bookFormat == .epub {
                EPUBReaderView(book: book, settings: settings)
            } else {
                PagedReaderView(book: book, settings: settings)
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    withAnimation(.snappy) {
                        showsSettings.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(book.title)
                            .font(.headline)
                            .lineLimit(1)

                        Image(systemName: showsSettings ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reading settings for \(book.title)")
            }
        }
        .overlay(alignment: .top) {
            if showsSettings {
                ReaderSettingsBar(
                    settings: settings,
                    supportsPublisherStyles: book.bookFormat == .epub
                ) {
                    withAnimation(.snappy) {
                        showsSettings = false
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
    }
}

private struct PagedReaderView: View {
    let book: Book
    @ObservedObject var settings: ReaderSettings

    @State private var currentPage = 0
    var body: some View {
        GeometryReader { geometry in
            let showsTwoPages = settings.pageLayout.showsTwoPages(for: geometry.size.width)
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
        .background(settings.theme.backgroundColor)
        .preferredColorScheme(settings.theme == .dark ? .dark : .light)
    }

    @ViewBuilder
    private func readerPages(showsTwoPages: Bool) -> some View {
        if showsTwoPages {
            HStack(spacing: 1) {
                    PageView(text: book.pages[currentPage], settings: settings)

                if currentPage + 1 < book.pages.count {
                    PageView(text: book.pages[currentPage + 1], settings: settings)
                } else {
                    Color(.systemBackground)
                }
            }
            .background(Color(.separator))
        } else {
            PageView(text: book.pages[currentPage], settings: settings)
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
    @ObservedObject var settings: ReaderSettings

    var body: some View {
        ScrollView {
            Text(text)
                .font(settings.font.swiftUIFont(size: 20 * CGFloat(settings.fontScale)))
                .foregroundStyle(settings.theme.textColor)
                .lineSpacing(8 * CGFloat(settings.lineHeight))
                .frame(maxWidth: 620, alignment: .topLeading)
                .padding(.horizontal, 32 * CGFloat(settings.pageMargins))
                .padding(.vertical, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settings.theme.backgroundColor)
    }
}

#Preview("Narrow") {
    NavigationStack {
        ReaderView(book: sampleBooks[0])
    }
}
