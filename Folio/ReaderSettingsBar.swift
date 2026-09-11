import SwiftUI

struct ReaderSettingsBar: View {
    @ObservedObject var settings: ReaderSettings
    let supportsPublisherStyles: Bool
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Reading Settings")
                    .font(.headline)

                Spacer()

                Button("Reset") {
                    settings.reset()
                }
                .font(.subheadline)

                Button(action: dismiss) {
                    Image(systemName: "chevron.up")
                        .font(.headline)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Close reading settings")
            }

            Picker("Theme", selection: $settings.theme) {
                ForEach(ReaderTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 18) {
                Button {
                    settings.fontScale = max(0.7, settings.fontScale - 0.1)
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .accessibilityLabel("Decrease font size")

                Slider(value: $settings.fontScale, in: 0.7...2, step: 0.1)

                Button {
                    settings.fontScale = min(2, settings.fontScale + 0.1)
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .accessibilityLabel("Increase font size")
            }

            HStack {
                Picker("Font", selection: $settings.font) {
                    ForEach(ReaderFont.allCases) { font in
                        Text(font.title).tag(font)
                    }
                }

                Spacer()

                Picker("Pages", selection: $settings.pageLayout) {
                    ForEach(ReaderPageLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
            }
            .pickerStyle(.menu)

            HStack {
                Label("Spacing", systemImage: "text.justify.leading")
                Slider(value: $settings.lineHeight, in: 1...2, step: 0.1)

                Label("Margins", systemImage: "arrow.left.and.right")
                Slider(value: $settings.pageMargins, in: 0.5...2, step: 0.1)
            }
            .font(.caption)

            if supportsPublisherStyles {
                Toggle("Use publisher formatting", isOn: $settings.usesPublisherStyles)
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(.regularMaterial)
        .clipShape(.rect(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }
}
