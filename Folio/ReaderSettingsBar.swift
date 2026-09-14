import SwiftUI

struct ReaderAppearanceSettings: View {
    @ObservedObject var settings: ReaderSettings
    @ObservedObject private var customFonts = CustomFontStore.shared
    let supportsPublisherStyles: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Appearance")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button("Reset") {
                    settings.reset()
                }
                .font(.subheadline)
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
                Picker("Font", selection: fontSelection) {
                    ForEach(ReaderFont.allCases) { font in
                        Text(font.title).tag(font.rawValue)
                    }

                    if !customFonts.fonts.isEmpty {
                        Divider()
                        ForEach(customFonts.fonts) { font in
                            Text(font.displayName).tag(font.id)
                        }
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

            Toggle("Page turn animation", isOn: $settings.usesPageTurnAnimation)
                .font(.subheadline)

            HStack {
                Label("Bottom progress", systemImage: "chart.bar.fill")
                    .font(.subheadline)

                Spacer()

                Picker("Bottom progress", selection: $settings.progressDisplay) {
                    ForEach(ReaderProgressDisplay.allCases) { display in
                        Text(display.title).tag(display)
                    }
                }
                .pickerStyle(.menu)
            }

            if supportsPublisherStyles {
                Toggle("Use publisher formatting", isOn: $settings.usesPublisherStyles)
                    .font(.subheadline)
            }
        }
    }

    private var fontSelection: Binding<String> {
        Binding(
            get: { settings.fontIdentifier },
            set: { settings.fontIdentifier = $0 }
        )
    }
}
