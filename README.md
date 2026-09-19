# Folio

<p align="center">
  <img src="Folio/Assets.xcassets/AppIcon.appiconset/FolioIcon.png" width="128" alt="Folio app icon">
</p>

<p align="center"><strong>A focused, beautiful ebook reader for iPhone.</strong></p>

Folio is a SwiftUI ebook reader project built for a calm, personal reading experience. Import your own books, customize the page, and keep your library organized without an account or a cloud service.

## Features

- EPUB reading powered by [Readium Swift Toolkit](https://github.com/readium/swift-toolkit)
- Import EPUB, PDF, and plain-text books
- EPUB table of contents and chapter navigation
- Centralized adaptive one-page and two-page reader layouts
- iPhone Duo hinge-assisted page turns: close slightly, then reopen to advance one page or spread
- Stable paginated EPUB reading with zero column drift
- Kindle-inspired interactive paper-curl page turns
- Optional bottom progress indicator for the whole book or current chapter
- Resume reading from the last saved location
- Bookmarks, highlights, and highlight notes
- Light, sepia, and dark themes
- Built-in font choices and imported custom fonts
- Edit title, author, and shelf metadata
- Edit publisher, publication year, language, ISBN, and description metadata
- Look up missing book metadata through the free Open Library Search API
- Search, sort, and filter the library
- Library-wide highlights, notes, and reading statistics
- Duplicate-import protection
- Cover artwork and fallback cover designs
- Reduce Motion support
- Local library storage with automatic recovery backups

## Requirements

- macOS with Xcode 27 beta or later
- iOS 27 SDK or later
- An Apple Developer account for installing Folio on a physical iPhone

Folio currently targets iOS 27 because it is being developed alongside Apple’s next-generation device and layout APIs. The project will continue to evolve as those SDKs stabilize.

## Getting started

1. Clone the repository:

   ```bash
   git clone https://github.com/DeweyDripp/Folio.git
   cd Folio
   ```

2. Open `Folio.xcodeproj` in Xcode Beta.
3. Let Xcode resolve the Readium Swift Toolkit package.
4. Select the **Folio** scheme and an iPhone simulator.
5. Press **Run** (⌘R).

To install on a physical iPhone, choose your development team under the Folio target’s **Signing & Capabilities** settings, connect your iPhone, select it as the run destination, and press **Run**.

The standard iPhone simulators remain the main supported development target. iPhone Duo hinge testing requires Apple’s Xcode 27.1 (or later) runtime; the hinge interaction is ignored on devices without a supported hinge.

## Using Folio

From the Library screen, tap **+** to import an EPUB, PDF, or text file. Tap a book to read it.

Inside a book:

- Tap the title to open the reader menu.
- Use **Appearance** for themes, fonts, layout, page-turn animation, and progress display.
- Use **Navigation** for the table of contents and bookmarks.
- Hold the upper-right corner to add or remove a page bookmark.
- Select text in an EPUB to create a highlight and optional note.

On a supported iPhone Duo, slightly close the device and reopen it to advance one page or spread. Folio ignores the intermediate hinge callbacks so one physical gesture turns only once.

Long-press a book in the library to edit its metadata or remove it.

## Project structure

```text
Folio/
├── FolioApp.swift                 App entry point
├── LibraryView.swift              Library, search, sorting, and shelves
├── ReaderView.swift               Text/PDF reader and adaptive layout
├── ReaderLayout.swift             Shared single/two-page layout decisions
├── EPUBReaderView.swift           EPUB reader model and Readium integration
├── EPUBNavigatorContainer.swift   UIKit bridge for the Readium navigator
├── PaperTurnController.swift      Interactive page-turn gesture lifecycle
├── PaperCurlView.swift             3D paper-curl rendering
├── ImportedBookLoader.swift        EPUB/PDF/text import and metadata loading
├── ImportedBookStore.swift         Library and cover-file persistence
├── ReadingProgressStore.swift      Resume positions and reading history
├── ReaderBookmarkStore.swift       Bookmark persistence
├── ReaderHighlightStore.swift      Highlight and note persistence
├── ReaderSettings.swift             Reader preferences
└── AppSettingsView.swift            App-level settings and custom fonts
```

## Testing

The project includes Swift Testing unit tests for:

- Backward-compatible library decoding
- Library sorting
- Progress persistence and backup recovery
- Duplicate file fingerprints

In Xcode, choose **Product → Test** (⌘U) to run the test suite.

## Development status

Folio is an actively developed personal project and is not yet an App Store release. The current focus is reader polish, broad EPUB compatibility, accessibility, performance, and reliable behavior across device sizes. EPUB reading is explicitly kept in paginated mode with zero column spacing to avoid accumulated horizontal drift while turning pages. iPhone Duo-specific layout work will be revisited as Apple’s SDK and simulator support matures.

## Acknowledgments

Folio’s EPUB rendering is built on the open-source [Readium Swift Toolkit](https://github.com/readium/swift-toolkit).
