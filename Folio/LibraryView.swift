import SwiftUI
import AVFoundation
import CryptoKit
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var readingProgress = ReadingProgressStore.shared
    @State private var importedBooks: [Book] = []
    @State private var isLoadingLibrary = true
    @State private var isShowingImporter = false
    @State private var isShowingAudiobookImporter = false
    @State private var audiobooks: [Audiobook] = []
    @State private var isImporting = false
    @State private var presentedError: LibraryError?
    @State private var bookToEdit: Book?
    @State private var bookToDelete: Book?
    @State private var searchText = ""
    @State private var selectedShelf = "__all_shelves__"
    @AppStorage("library-sort") private var sortRawValue = LibrarySortOption.recent.rawValue
    @AppStorage("library-show-progress") private var showProgress = true

    @AppStorage("library-grid-size") private var gridSize = 0.0

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 140 + gridSize * 70, maximum: 230), spacing: 24)]
    }

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            iPadLayout
        } else {
            phoneLayout
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            List {
                Section("Folio") {
                    NavigationLink {
                        phoneLayout
                    } label: {
                        Label("Library", systemImage: "books.vertical")
                    }
                }
                Section {
                    NavigationLink {
                        AppSettingsView(books: importedBooks)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    NavigationLink {
                        LibraryInsightsView(books: importedBooks)
                    } label: {
                        Label("Insights", systemImage: "chart.bar.xaxis")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Folio")
        } detail: {
            phoneLayout
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var phoneLayout: some View {
        NavigationStack {
            Group {
                if isLoadingLibrary {
                    ProgressView("Loading library…")
                } else if importedBooks.isEmpty {
                    ContentUnavailableView {
                        Label("Your Library Is Empty", systemImage: "books.vertical")
                    } description: {
                        Text("Tap the plus button to import an EPUB, PDF, or text file.")
                    }
                } else if visibleBooks.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 28) {
                            ForEach(visibleBooks) { book in
                                NavigationLink {
                                    ReaderView(book: book)
                                } label: {
                                    BookCoverView(
                                        book: book,
                                        progress: showProgress ? readingProgress.progress(for: book.id) : nil
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        bookToEdit = book
                                    } label: {
                                        Label("Book Info", systemImage: "info.circle")
                                    }

                                    Button(role: .destructive) {
                                        bookToDelete = book
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        AppSettingsView(books: importedBooks)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        LibraryInsightsView(books: importedBooks)
                    } label: {
                        Label("Insights", systemImage: "chart.bar.xaxis")
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Picker("Sort By", selection: sortSelection) {
                            ForEach(LibrarySortOption.allCases) { option in
                                Label(option.title, systemImage: option.systemImage)
                                    .tag(option)
                            }
                        }

                        if !shelves.isEmpty {
                            Divider()
                            Picker("Shelf", selection: $selectedShelf) {
                                Text("All Shelves").tag(Self.allShelves)
                                Text("Unfiled").tag(Self.unfiledShelf)
                                ForEach(shelves, id: \.self) { shelf in
                                    Text(shelf).tag(shelf)
                                }
                            }
                        }
                    } label: {
                        Label("Organize Library", systemImage: "arrow.up.arrow.down.circle")
                    }

                    NavigationLink {
                        AudiobooksLibraryView(audiobooks: audiobooks)
                    } label: {
                        Label("Audiobooks", systemImage: "headphones")
                    }
                    Menu {
                        Button { isShowingImporter = true } label: {
                            Label("Book", systemImage: "book")
                        }
                        Button { isShowingAudiobookImporter = true } label: {
                            Label("Audiobook", systemImage: "headphones")
                        }
                    } label: {
                        Label("Import", systemImage: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $isShowingImporter,
                allowedContentTypes: [.plainText, .pdf, .epub]
            ) { result in
                Task {
                    await importBook(from: result)
                }
            }
            .fileImporter(isPresented: $isShowingAudiobookImporter, allowedContentTypes: [.audio, .folder], allowsMultipleSelection: true) { result in
                Task { await importAudiobook(from: result) }
            }
            .searchable(text: $searchText, prompt: "Search titles and authors")
            .sheet(item: $bookToEdit) { book in
                BookMetadataEditor(book: book) { updatedBook in
                    updateBook(updatedBook)
                }
            }
            .confirmationDialog(
                "Remove Book?",
                isPresented: isShowingDeleteConfirmation,
                titleVisibility: .visible,
                presenting: bookToDelete
            ) { book in
                Button("Delete \(book.title)", role: .destructive) {
                    deleteBook(book)
                }
                Button("Cancel", role: .cancel) { }
            } message: { book in
                Text("This removes \(book.title) and its reading progress from Folio. Your original imported file is not affected.")
            }
            .overlay {
                if isImporting {
                    ProgressView("Importing book…")
                        .padding(22)
                        .folioControlPanel(cornerRadius: 16)
                }
            }
            .alert(item: $presentedError) { error in
                Alert(
                    title: Text(error.title),
                    message: Text(error.message),
                    dismissButton: .cancel(Text("OK"))
                )
            }
            .task {
                loadLibrary()
                audiobooks = (try? AudiobookStore.load()) ?? []
                if let message = readingProgress.errorMessage {
                    presentedError = LibraryError(title: "Couldn’t Load Progress", message: message)
                    readingProgress.clearError()
                }
            }
            .onChange(of: readingProgress.errorMessage) { _, message in
                guard let message else { return }
                presentedError = LibraryError(title: "Couldn’t Save Progress", message: message)
                readingProgress.clearError()
            }
            .onReceive(NotificationCenter.default.publisher(for: .folioLibraryDidChange)) { _ in
                loadLibrary()
            }
        }
    }

    private static let allShelves = "__all_shelves__"
    private static let unfiledShelf = "__unfiled_shelf__"

    private var sortSelection: Binding<LibrarySortOption> {
        Binding(
            get: { LibrarySortOption(rawValue: sortRawValue) ?? .recent },
            set: { sortRawValue = $0.rawValue }
        )
    }

    private var shelves: [String] {
        Set(importedBooks.compactMap(\.normalizedShelf)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var visibleBooks: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = importedBooks.filter { book in
            let matchesSearch = query.isEmpty
                || book.title.localizedCaseInsensitiveContains(query)
                || book.author.localizedCaseInsensitiveContains(query)
            let matchesShelf = selectedShelf == Self.allShelves
                || (selectedShelf == Self.unfiledShelf && book.normalizedShelf == nil)
                || book.normalizedShelf == selectedShelf
            return matchesSearch && matchesShelf
        }

        return sortSelection.wrappedValue.sort(filtered) { bookID in
            readingProgress.progress(for: bookID)?.updatedAt
        }
    }

    private var isShowingDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { bookToDelete != nil },
            set: { if !$0 { bookToDelete = nil } }
        )
    }

    private func updateBook(_ updatedBook: Book) {
        guard let index = importedBooks.firstIndex(where: { $0.id == updatedBook.id }) else {
            return
        }

        var updatedBooks = importedBooks
        updatedBooks[index] = updatedBook
        do {
            try ImportedBookStore.save(updatedBooks)
            importedBooks = updatedBooks
        } catch {
            showStorageError()
        }
    }

    private func deleteBook(_ book: Book) {
        let remainingBooks = importedBooks.filter { $0.id != book.id }
        do {
            try ImportedBookStore.save(remainingBooks)
            importedBooks = remainingBooks
            ReaderBookmarkStore.removeAll(for: book.id)
            ReaderHighlightStore.removeAll(for: book.id)
            readingProgress.remove(for: book.id)
            EPUBProgressStore.removeLegacyProgress(for: book.id)
            bookToDelete = nil

            do {
                try ImportedBookStore.removeImportedFiles(for: book)
            } catch {
                presentedError = LibraryError(
                    title: "Book Removed",
                    message: "The book was removed from your library, but Folio couldn’t finish cleaning up its stored file."
                )
            }
        } catch {
            showStorageError()
        }
    }

    @MainActor
    private func importBook(from result: Result<URL, Error>) async {
        isImporting = true
        defer { isImporting = false }

        do {
            let url = try result.get()
            let fingerprint = try ImportedBookLoader.fingerprint(for: url)
            guard !LibraryImportValidator.containsDuplicateBook(fingerprint: fingerprint, in: importedBooks) else {
                throw DuplicateBookError()
            }

            let book = try await ImportedBookLoader.load(from: url, fingerprint: fingerprint)
            var updatedBooks = importedBooks
            updatedBooks.insert(book, at: 0)
            do {
                try ImportedBookStore.save(updatedBooks)
                importedBooks = updatedBooks
            } catch {
                try? ImportedBookStore.removeImportedFiles(for: book)
                throw error
            }
        } catch {
            presentedError = LibraryError(title: "Couldn’t Import Book", message: error.localizedDescription)
        }
    }

    private func loadLibrary() {
        isLoadingLibrary = true
        Task {
            do {
                let books = try await Task.detached(priority: .userInitiated) {
                    try ImportedBookStore.load()
                }.value
                importedBooks = books
            } catch {
                presentedError = LibraryError(
                    title: "Couldn’t Load Library",
                    message: "Folio couldn’t read its library information. Your imported book files have not been deleted."
                )
            }
            isLoadingLibrary = false
        }
    }

    private func importAudiobook(from result: Result<[URL], Error>) async {
        var copiedFileNames: [String] = []
        do {
            let selected = try result.get()
            let accessStates = selected.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer {
                for (url, didStart) in accessStates where didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let expanded = selected.flatMap { url -> [URL] in
                if url.hasDirectoryPath {
                    return (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                }
                return [url]
            }
            let urls = expanded.filter { ["mp3", "m4a", "aac", "wav"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            guard !urls.isEmpty else { return }
            let id = UUID()
            var chapters: [AudiobookChapter] = []
            var seenFingerprints = LibraryImportValidator.existingAudiobookFingerprints(in: audiobooks)
            for (index, url) in urls.enumerated() {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                let name = "\(id.uuidString)-\(index).\(url.pathExtension)"
                let asset = AVURLAsset(url: url)
                let seconds = try? await asset.load(.duration).seconds
                let duration = seconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
                let fingerprint = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
                guard LibraryImportValidator.canInsertAudiobookFingerprint(fingerprint, into: &seenFingerprints) else {
                    throw DuplicateBookError()
                }
                try FileManager.default.copyItem(at: url, to: AudiobookStore.audioDirectory.appending(path: name))
                copiedFileNames.append(name)
                chapters.append(AudiobookChapter(id: UUID(), title: url.deletingPathExtension().lastPathComponent, fileName: name, duration: duration, fingerprint: fingerprint))
            }
            let asset = AVURLAsset(url: urls[0])
            let metadata = (try? await asset.load(.commonMetadata)) ?? []
            var artwork: Data?
            if let item = metadata.first(where: { $0.commonKey?.rawValue == "artwork" }) {
                artwork = try? await item.load(.dataValue)
            }
            let audiobook = Audiobook(id: id, title: urls.first!.deletingLastPathComponent().lastPathComponent, author: "Audiobook", chapters: chapters, importedAt: Date(), coverData: artwork)
            var updated = audiobooks; updated.insert(audiobook, at: 0); try AudiobookStore.save(updated); audiobooks = updated
        } catch {
            for fileName in copiedFileNames {
                try? FileManager.default.removeItem(at: AudiobookStore.audioDirectory.appending(path: fileName))
            }
            presentedError = LibraryError(title: "Couldn’t Import Audiobook", message: error.localizedDescription)
        }
    }

    private func showStorageError() {
        presentedError = LibraryError(
            title: "Couldn’t Save Library",
            message: "Folio couldn’t save that change. Check that your device has available storage, then try again."
        )
    }
}

private struct LibraryError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct DuplicateBookError: LocalizedError {
    var errorDescription: String? {
        "That exact book is already in your Folio library."
    }
}

private extension UTType {
    static let epub = UTType(filenameExtension: "epub")!
}

#Preview {
    LibraryView()
}
