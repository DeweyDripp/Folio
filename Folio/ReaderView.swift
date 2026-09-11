import SwiftUI

struct ReaderView: View {
    let book: Book
    @StateObject private var settings = ReaderSettings()
    @State private var showsMenu = false

    var body: some View {
        Group {
            if book.bookFormat == .epub {
                EPUBReaderView(
                    book: book,
                    settings: settings,
                    showsMenu: $showsMenu
                )
            } else {
                PagedReaderView(
                    book: book,
                    settings: settings,
                    showsMenu: $showsMenu
                )
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    withAnimation(.snappy) {
                        showsMenu.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(book.title)
                            .font(.headline)
                            .lineLimit(1)

                        Image(systemName: showsMenu ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reader menu for \(book.title)")
            }
        }
    }
}

private struct PagedReaderView: View {
    let book: Book
    @ObservedObject var settings: ReaderSettings
    @Binding var showsMenu: Bool
    @StateObject private var bookmarks: ReaderBookmarkStore

    @State private var currentPage = 0

    init(book: Book, settings: ReaderSettings, showsMenu: Binding<Bool>) {
        self.book = book
        self.settings = settings
        _showsMenu = showsMenu
        _bookmarks = StateObject(wrappedValue: ReaderBookmarkStore(bookID: book.id))
    }

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
        .overlay(alignment: .top) {
            if showsMenu {
                ReaderMenuBar(
                    settings: settings,
                    bookmarks: bookmarks,
                    supportsPublisherStyles: false,
                    chapters: chapters,
                    isCurrentLocationBookmarked: bookmarks.containsPage(currentPage),
                    selectChapter: { chapter in
                        guard let page = Int(chapter.id) else { return }
                        currentPage = page
                        closeMenu()
                    },
                    selectBookmark: { bookmark in
                        guard let page = bookmark.pageIndex else { return }
                        currentPage = page
                        closeMenu()
                    },
                    toggleCurrentBookmark: {
                        bookmarks.togglePage(currentPage)
                    },
                    dismiss: closeMenu
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .background(settings.theme.backgroundColor)
        .preferredColorScheme(settings.theme == .dark ? .dark : .light)
    }

    private var chapters: [ReaderChapter] {
        book.pages.indices.map { page in
            ReaderChapter(id: String(page), title: "Page \(page + 1)", depth: 0)
        }
    }

    private func closeMenu() {
        withAnimation(.snappy) {
            showsMenu = false
        }
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
