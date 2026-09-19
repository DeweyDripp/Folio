import SwiftUI
import UIKit

struct ReaderView: View {
    let book: Book
    @StateObject private var settings = ReaderSettings()
    @State private var showsMenu = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

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
            .toolbar(isLandscape ? .hidden : .visible, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                if isLandscape {
                    landscapeHeader
                }
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
        .onAppear {
            ReadingProgressStore.shared.markOpened(book.id)
            UIApplication.shared.isIdleTimerDisabled = settings.keepsScreenAwake
        }
        .onChange(of: settings.keepsScreenAwake) { _, keepsAwake in
            UIApplication.shared.isIdleTimerDisabled = keepsAwake
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .background(NavigationBackGestureDisabler())
    }

    private var landscapeHeader: some View {
        HStack(spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Back to Library")

            Spacer()

            Button {
                withAnimation(.snappy) {
                    showsMenu.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(book.title)
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: showsMenu ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reader menu for \(book.title)")

            Spacer()

            // Balances the back button so the title stays visually centered.
            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .background(.clear)
    }
}

private struct NavigationBackGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) { }

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            super.viewWillDisappear(animated)
        }
    }
}

private struct PagedReaderView: View {
    let book: Book
    @ObservedObject var settings: ReaderSettings
    @Binding var showsMenu: Bool
    @StateObject private var bookmarks: ReaderBookmarkStore
    @StateObject private var highlights: ReaderHighlightStore

    @State private var currentPage = 0
    @State private var activePageStep = 1
    @State private var restoredProgress = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(
        book: Book,
        settings: ReaderSettings,
        showsMenu: Binding<Bool>
    ) {
        self.book = book
        self.settings = settings
        _showsMenu = showsMenu
        _bookmarks = StateObject(wrappedValue: ReaderBookmarkStore(bookID: book.id))
        _highlights = StateObject(wrappedValue: ReaderHighlightStore(bookID: book.id))
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = ReaderLayout.resolve(
                pageLayout: settings.pageLayout,
                horizontalSizeClass: horizontalSizeClass,
                geometry: geometry,
            )
            let showsTwoPages = layout.showsTwoPages
            let pageStep = showsTwoPages ? 2 : 1

            VStack(spacing: 0) {
                pageContainer(
                    showsTwoPages: showsTwoPages,
                    pageStep: pageStep,
                    gutterWidth: layout.gutterWidth
                )

                Divider()

                readerControls(pageStep: pageStep)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.bar)

                if settings.progressDisplay != .hidden {
                    ReaderProgressBar(title: "Book", fraction: pageProgress)
                }
            }
            .onAppear {
                activePageStep = pageStep
            }
            .onChange(of: showsTwoPages) { _, isWide in
                activePageStep = isWide ? 2 : 1
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
                    highlights: highlights,
                    supportsPublisherStyles: false,
                    supportsHighlights: false,
                    chapters: chapters,
                    currentLocationTitle: "Page \(currentPage + 1)",
                    progressFraction: pageProgress,
                    isCurrentLocationBookmarked: bookmarks.containsPage(currentPage),
                    selectChapter: { chapter in
                        guard let page = Int(chapter.id) else { return }
                        go(to: page)
                        closeMenu()
                    },
                    selectBookmark: { bookmark in
                        guard let page = bookmark.pageIndex else { return }
                        go(to: page)
                        closeMenu()
                    },
                    toggleCurrentBookmark: {
                        bookmarks.togglePage(currentPage)
                    },
                    selectHighlight: { _ in },
                    editHighlight: { _ in },
                    dismiss: closeMenu
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !showsMenu {
                BookmarkRibbon(
                    isBookmarked: bookmarks.containsPage(currentPage),
                    toggle: { bookmarks.togglePage(currentPage) }
                )
            }
        }
        .background(settings.theme.backgroundColor)
        .preferredColorScheme(settings.theme == .dark ? .dark : .light)
        .onAppear {
            restoreProgressIfNeeded()
        }
        .onChange(of: currentPage) { _, page in
            saveProgress(page)
        }
    }

    private var chapters: [ReaderChapter] {
        book.pages.indices.map { page in
            ReaderChapter(id: String(page), title: "Page \(page + 1)", depth: 0)
        }
    }

    private var pageProgress: Double {
        guard !book.pages.isEmpty else { return 0 }
        return min(1, Double(currentPage + activePageStep) / Double(book.pages.count))
    }

    private func closeMenu() {
        withAnimation(.snappy) {
            showsMenu = false
        }
    }

    @ViewBuilder
    private func pageContainer(showsTwoPages: Bool, pageStep: Int, gutterWidth: CGFloat) -> some View {
        PaperPageContainer(
            page: $currentPage,
            pageCount: book.pages.count,
            step: pageStep,
            animated: settings.usesPageTurnAnimation && !reduceMotion,
            paperColor: settings.theme.backgroundColor
        ) { page in
            readerPages(startingAt: page, showsTwoPages: showsTwoPages, gutterWidth: gutterWidth)
        }
    }

    @ViewBuilder
    private func readerPages(startingAt page: Int, showsTwoPages: Bool, gutterWidth: CGFloat) -> some View {
        if showsTwoPages {
            HStack(spacing: 0) {
                PageView(text: book.pages[page], settings: settings)

                Color.clear
                    .frame(width: gutterWidth)
                    .accessibilityHidden(true)

                if page + 1 < book.pages.count {
                    PageView(text: book.pages[page + 1], settings: settings)
                } else {
                    settings.theme.backgroundColor
                }
            }
            .background(settings.theme.backgroundColor)
        } else {
            PageView(text: book.pages[page], settings: settings)
        }
    }


    private func readerControls(pageStep: Int) -> some View {
        HStack {
            Button {
                go(to: max(0, currentPage - pageStep))
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
                go(to: min(book.pages.count - 1, currentPage + pageStep))
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


    private func go(to page: Int) {
        guard page != currentPage, book.pages.indices.contains(page) else { return }
        let alignedPage = page - (page % activePageStep)

        currentPage = alignedPage
    }

    private func restoreProgressIfNeeded() {
        guard !restoredProgress else { return }
        restoredProgress = true
        let savedPage = ReadingProgressStore.shared.progress(for: book.id)?.pageIndex ?? 0
        guard book.pages.indices.contains(savedPage) else { return }
        currentPage = savedPage - (savedPage % activePageStep)
        saveProgress(currentPage)
    }

    private func saveProgress(_ page: Int) {
        guard book.pages.indices.contains(page) else { return }
        ReadingProgressStore.shared.savePage(
            page,
            pageCount: book.pages.count,
            title: "Page \(page + 1)",
            for: book.id
        )
    }
}

private struct PageView: View {
    let text: String
    @ObservedObject var settings: ReaderSettings

    var body: some View {
        ScrollView {
            Text(text)
                .font(settings.swiftUIFont(size: 20 * CGFloat(settings.fontScale)))
                .foregroundStyle(settings.theme.textColor)
                .lineSpacing(8 * CGFloat(settings.lineHeight))
                .frame(maxWidth: 900, alignment: .topLeading)
                .padding(.horizontal, 32 * CGFloat(settings.pageMargins))
                .padding(.vertical, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settings.theme.backgroundColor)
    }
}

#Preview("Narrow") {
    NavigationStack {
        ReaderView(
            book: Book(
                title: "Preview Book",
                author: "Folio",
                coverSymbol: "book.closed.fill",
                coverColorName: "indigo",
                pages: ["This is a preview page for the Folio reader."]
            )
        )
    }
}
