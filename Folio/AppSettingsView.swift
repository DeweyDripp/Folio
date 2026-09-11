import SwiftUI
import UniformTypeIdentifiers

struct AppSettingsView: View {
    @StateObject private var readerSettings = ReaderSettings()
    @ObservedObject private var customFonts = CustomFontStore.shared
    @State private var showsFontImporter = false
    @State private var fontImportError: String?

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
    }

    private var showsFontImportError: Binding<Bool> {
        Binding(
            get: { fontImportError != nil },
            set: { if !$0 { fontImportError = nil } }
        )
    }
}
