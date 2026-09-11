import SwiftUI

enum ReaderMenuSection {
    case appearance
    case navigation
}

struct ReaderMenuBar: View {
    @ObservedObject var settings: ReaderSettings
    @ObservedObject var bookmarks: ReaderBookmarkStore
    let supportsPublisherStyles: Bool
    let chapters: [ReaderChapter]
    let isCurrentLocationBookmarked: Bool
    let selectChapter: (ReaderChapter) -> Void
    let selectBookmark: (ReaderBookmark) -> Void
    let toggleCurrentBookmark: () -> Void
    let dismiss: () -> Void

    @State private var section: ReaderMenuSection = .appearance

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Reader Menu")
                    .font(.headline)

                Spacer()

                Button(action: dismiss) {
                    Image(systemName: "chevron.up")
                        .font(.headline)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Close reader menu")
            }

            HStack(spacing: 12) {
                sectionButton(title: "Appearance", systemImage: "textformat", section: .appearance)
                sectionButton(title: "Navigation", systemImage: "list.bullet", section: .navigation)
            }

            Divider()

            switch section {
            case .appearance:
                ReaderAppearanceSettings(
                    settings: settings,
                    supportsPublisherStyles: supportsPublisherStyles
                )

            case .navigation:
                navigationPanel
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(.regularMaterial)
        .clipShape(.rect(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }

    private func sectionButton(
        title: String,
        systemImage: String,
        section targetSection: ReaderMenuSection
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                section = targetSection
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(section == targetSection ? Color.accentColor : .secondary)
            .background(
                section == targetSection ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
    }

    private var navigationPanel: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Bookmarks", systemImage: "bookmark")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Button(action: toggleCurrentBookmark) {
                        Label(
                            isCurrentLocationBookmarked ? "Remove" : "Add",
                            systemImage: isCurrentLocationBookmarked ? "bookmark.slash" : "bookmark.fill"
                        )
                    }
                    .font(.subheadline)
                }

                if bookmarks.bookmarks.isEmpty {
                    Text("No bookmarks yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(bookmarks.bookmarks) { bookmark in
                        HStack(spacing: 8) {
                            Button {
                                selectBookmark(bookmark)
                            } label: {
                                Label(bookmark.title, systemImage: "bookmark.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                bookmarks.remove(bookmark)
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 30, height: 30)
                            }
                            .accessibilityLabel("Delete bookmark \(bookmark.title)")
                        }
                        .font(.subheadline)
                        .padding(.vertical, 4)
                    }
                }

                Divider()
                    .padding(.vertical, 6)

                Label("Contents", systemImage: "list.bullet")
                    .font(.subheadline.weight(.semibold))

                if chapters.isEmpty {
                    Text("No table of contents available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(chapters) { chapter in
                        Button {
                            selectChapter(chapter)
                        } label: {
                            Text(chapter.title)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, CGFloat(chapter.depth) * 16)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxHeight: 360)
    }
}
