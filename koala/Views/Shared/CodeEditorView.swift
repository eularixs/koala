import SwiftUI

struct CodeEditorView: View {
    @Binding var text: String
    var language: String = "json"
    var minHeight: CGFloat = 160

    @State private var formatError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider()
            editorArea
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 8) {
            Text(language.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

            Spacer()

            if language.lowercased() == "json" {
                formatButton
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var formatButton: some View {
        Button("Format") {
            formatJSON()
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(Color.accentColor)
        .help("Pretty-print JSON (Cmd+Shift+F)")
    }

    private var editorArea: some View {
        CodeTextView(text: $text)
            .frame(minHeight: minHeight)
            .padding(4)
    }

    private func formatJSON() {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            formatError = "Invalid JSON"
            return
        }
        text = str
        formatError = nil
    }
}

// MARK: - Preview

#Preview("CodeEditorView — JSON") {
    @Previewable @State var code = """
    {"name":"Koala","version":"1.0","features":["http-client","mock-server","collaboration"]}
    """

    return VStack(spacing: 16) {
        Text("Code Editor").font(.headline)
        CodeEditorView(text: $code, language: "json", minHeight: 200)
    }
    .padding()
    .frame(width: 560)
}

#Preview("CodeEditorView — Raw") {
    @Previewable @State var script = "SELECT * FROM users WHERE id = 1;"

    return CodeEditorView(text: $script, language: "sql", minHeight: 120)
        .padding()
        .frame(width: 560)
}
