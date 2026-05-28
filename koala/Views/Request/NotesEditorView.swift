import SwiftUI

// MARK: - NotesEditorView
//
// Per-request markdown notes pane. Three display modes:
//  - .edit: full-width TextEditor only
//  - .preview: full-width rendered markdown only
//  - .split: HSplitView with editor on the left, preview on the right
//
// Preview uses `AttributedString(markdown:)` (native, macOS 14+). On parse
// failure (malformed inline markdown) we fall back to plain text.

struct NotesEditorView: View {
    @Binding var request: KoalaRequest

    enum Mode: String, CaseIterable, Identifiable {
        case edit    = "Edit"
        case preview = "Preview"
        case split   = "Split"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .split

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var notesBinding: Binding<String> {
        Binding(
            get: { request.notes ?? "" },
            set: { newValue in
                request.notes = newValue.isEmpty ? nil : newValue
            }
        )
    }

    private var notesText: String { request.notes ?? "" }

    private var wordCount: Int {
        notesText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
    }

    private var characterCount: Int { notesText.count }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .labelsHidden()

            Spacer()

            Text("\(wordCount) word\(wordCount == 1 ? "" : "s") · \(characterCount) char\(characterCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("·")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text("Edited \(Self.timestampFormatter.string(from: request.updatedAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .edit:
            editor
        case .preview:
            preview
        case .split:
            HSplitView {
                editor
                    .frame(minWidth: 200, idealWidth: 360)
                preview
                    .frame(minWidth: 200, idealWidth: 360)
            }
        }
    }

    // MARK: Editor

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: notesBinding)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))

            if notesText.isEmpty {
                Text("Document this request — supports **markdown**, `code`, links, lists.")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Preview

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if notesText.isEmpty {
                    Text("Nothing to preview yet.")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(renderedMarkdown(notesText))
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// Parse markdown with full multiline support (preserves paragraphs / lists / code blocks).
    /// Falls back to plain `AttributedString` on parse failure.
    private func renderedMarkdown(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full
        )
        if let parsed = try? AttributedString(markdown: source, options: options) {
            return parsed
        }
        return AttributedString(source)
    }
}

// MARK: - Preview

private struct NotesEditorPreview: View {
    @State private var request = KoalaRequest(
        name: "Sample",
        notes: """
        # Notes
        Document this **request**.

        - point one
        - point two

        Inline `code` and a [link](https://example.com).
        """
    )
    var body: some View {
        NotesEditorView(request: $request)
    }
}

#Preview("NotesEditorView") {
    NotesEditorPreview()
        .frame(width: 800, height: 500)
}
