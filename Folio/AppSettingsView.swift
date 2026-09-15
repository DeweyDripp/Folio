import SwiftUI
import UniformTypeIdentifiers

struct AppSettingsView: View {
    @StateObject private var readerSettings = ReaderSettings()
    @ObservedObject private var customFonts = CustomFontStore.shared
    @State private var showsFontImporter = false
    @State private var fontImportError: String?
    @AppStorage("library-sort") private var librarySort = LibrarySortOption.recent.rawValue
    @AppStorage("library-show-progress") private var showProgress = true
    @AppStorage("library-grid-size") private var gridSize = 0.0
    @AppStorage("metadata-auto-suggest") private var metadataAutoSuggest = false
    let books: [Book]
    @State private var backupError: String?
    @State private var backupDocument: FolioBackupDocument?
    @State private var showsBackupImporter = false
    @State private var pendingBackupData: Data?
    @State private var showsRestoreConfirmation = false

    init(books: [Book] = []) { self.books = books }

    var body: some View {
        Form {
            Section {
                if customFonts.fonts.isEmpty {
                    Text("Imported fonts will appear in the reader’s font menu.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customFonts.fonts) { font in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(font.displayName)
                                    .font(.custom(font.id, size: 19))
                                Text(font.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                if readerSettings.customFontName == font.id {
                                    readerSettings.fontIdentifier = ReaderFont.serif.rawValue
                                }
                                customFonts.remove(font)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Delete \(font.displayName)")
                        }
                    }
                }

                Button {
                    showsFontImporter = true
                } label: {
                    Label("Import Font", systemImage: "plus")
                }
            } header: {
                Text("Custom Fonts")
            } footer: {
                Text("Import OpenType or TrueType fonts you have permission to use.")
            }

            Section("Library") {
                Picker("Default sort", selection: $librarySort) {
                    ForEach(LibrarySortOption.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                Toggle("Show progress on book covers", isOn: $showProgress)
                HStack {
                    Text("Book size")
                    Slider(value: $gridSize, in: 0...1)
                }
            }

            Section("Reader Behavior") {
                Toggle("Keep screen awake while reading", isOn: $readerSettings.keepsScreenAwake)
                Toggle("Page-turn haptics", isOn: $readerSettings.usesPageTurnHaptics)
            }

            Section("Metadata") {
                Toggle("Suggest metadata after importing", isOn: $metadataAutoSuggest)
                Text("Folio will still ask you to choose the matching Open Library edition.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Backup") {
                Button {
                    do {
                        let url = try FolioBackupService.makeBackup(books: books)
                        backupDocument = FolioBackupDocument(data: try Data(contentsOf: url))
                    } catch { backupError = error.localizedDescription }
                } label: {
                    Label("Export Library Backup", systemImage: "square.and.arrow.up")
                }
                Button { showsBackupImporter = true } label: {
                    Label("Import Library Backup", systemImage: "square.and.arrow.down")
                }
                Text("Includes books, metadata, reading progress, bookmarks, and highlights. Save it to Files or AirDrop it to another device.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("App", value: "Folio")
                LabeledContent("Reader", value: "Readium")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showsFontImporter,
            allowedContentTypes: [.font]
        ) { result in
            do {
                try customFonts.importFont(from: result.get())
            } catch {
                fontImportError = error.localizedDescription
            }
        }
        .alert("Couldn’t Import Font", isPresented: showsFontImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(fontImportError ?? "Please try another font file.")
        }
        .alert("Couldn’t Create Backup", isPresented: Binding(get: { backupError != nil }, set: { if !$0 { backupError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(backupError ?? "Please try again.") }
        .fileExporter(
            isPresented: Binding(get: { backupDocument != nil }, set: { if !$0 { backupDocument = nil } }),
            document: backupDocument,
            contentType: .json,
            defaultFilename: "Folio-Backup.json"
        ) { result in
            if case .failure(let error) = result { backupError = error.localizedDescription }
            backupDocument = nil
        }
        .fileImporter(isPresented: $showsBackupImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                guard url.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
                defer { url.stopAccessingSecurityScopedResource() }
                pendingBackupData = try Data(contentsOf: url)
                showsRestoreConfirmation = true
            } catch { backupError = error.localizedDescription }
        }
        .confirmationDialog("Restore Folio Backup?", isPresented: $showsRestoreConfirmation, titleVisibility: .visible) {
            Button("Restore and Replace Library", role: .destructive) {
                do { if let data = pendingBackupData { try FolioBackupService.restore(from: data) } }
                catch { backupError = error.localizedDescription }
                pendingBackupData = nil
            }
            Button("Cancel", role: .cancel) { pendingBackupData = nil }
        } message: {
            Text("This replaces the current library metadata and reading data. Your original book files are not deleted.")
        }
    }

    private var showsFontImportError: Binding<Bool> {
        Binding(
            get: { fontImportError != nil },
            set: { if !$0 { fontImportError = nil } }
        )
    }
}
