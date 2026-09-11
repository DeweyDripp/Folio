import SwiftUI

struct HighlightNoteEditor: View {
    let highlight: ReaderHighlight
    let save: (String, ReaderHighlightColor) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var color: ReaderHighlightColor

    init(highlight: ReaderHighlight, save: @escaping (String, ReaderHighlightColor) -> Void) {
        self.highlight = highlight
        self.save = save
        _note = State(initialValue: highlight.note)
        _color = State(initialValue: highlight.color)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Highlighted Text") {
                    Text(highlight.text)
                        .foregroundStyle(.secondary)
                }

                Section("Color") {
                    HStack(spacing: 18) {
                        ForEach(ReaderHighlightColor.allCases) { choice in
                            Button {
                                color = choice
                            } label: {
                                Circle()
                                    .fill(choice.swiftUIColor)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if color == choice {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.black.opacity(0.7))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.title)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Section("Note") {
                    TextEditor(text: $note)
                        .frame(minHeight: 130)
                }
            }
            .navigationTitle("Highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(note.trimmingCharacters(in: .whitespacesAndNewlines), color)
                        dismiss()
                    }
                }
            }
        }
    }
}

extension ReaderHighlightColor {
    var swiftUIColor: Color {
        switch self {
        case .yellow: Color(red: 1, green: 0.82, blue: 0.2)
        case .pink: Color(red: 1, green: 0.48, blue: 0.62)
        case .green: Color(red: 0.42, green: 0.82, blue: 0.48)
        case .blue: Color(red: 0.35, green: 0.66, blue: 1)
        }
    }
}
