import SwiftUI

struct URLBarView: View {
    @Binding var request: KoalaRequest
    let isSending: Bool
    let onSend: () -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                MethodPickerView(method: $request.method)

                TextField("https://api.example.com/endpoint or {{base_url}}/api/...", text: $request.url)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .onChange(of: request.url) { _, newValue in
                        autoParseCurlIfPasted(newValue)
                    }

                sendButton
            }

            if !variableTokens.isEmpty {
                variableChips
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Variable Chips

    private var variableChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(variableTokens, id: \.self) { name in
                    chip(for: name)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func chip(for name: String) -> some View {
        let resolved = lookupValue(name)
        let isResolved = resolved != nil
        let color: Color = isResolved ? .green : .orange
        return HStack(spacing: 4) {
            Image(systemName: isResolved ? "leaf.fill" : "questionmark.circle")
                .font(.caption2)
            Text("{{\(name)}}")
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
            if let v = resolved {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(v)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
            } else {
                Text("not in env")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 0.5))
        .foregroundStyle(color)
        .help(isResolved ? "Resolved from \(sourceLabel(name)): \(resolved ?? "")" : "Add `\(name)` to an active environment or global variables")
    }

    // MARK: - Token Extraction

    private var variableTokens: [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\{\{([^{}]+)\}\}"#) else { return [] }
        let url = request.url
        let range = NSRange(url.startIndex..., in: url)
        var seen = Set<String>()
        var out: [String] = []
        for match in regex.matches(in: url, range: range) {
            guard let r = Range(match.range(at: 1), in: url) else { continue }
            let name = String(url[r]).trimmingCharacters(in: .whitespaces)
            if !seen.contains(name) { seen.insert(name); out.append(name) }
        }
        return out
    }

    private func lookupValue(_ name: String) -> String? {
        if let env = appState.selectedEnvironment,
           let v = env.variables.first(where: { $0.key == name && $0.isEnabled }) {
            return v.value
        }
        if let g = appState.globalVariables.first(where: { $0.key == name && $0.isEnabled }) {
            return g.value
        }
        return nil
    }

    private func sourceLabel(_ name: String) -> String {
        if let env = appState.selectedEnvironment,
           env.variables.contains(where: { $0.key == name && $0.isEnabled }) {
            return "environment \"\(env.name)\""
        }
        if appState.globalVariables.contains(where: { $0.key == name && $0.isEnabled }) {
            return "global variables"
        }
        return "?"
    }

    private var sendButton: some View {
        Button(action: onSend) {
            ZStack {
                Text("Send")
                    .opacity(isSending ? 0 : 1)
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
            }
            .frame(width: 56, height: 16)
        }
        .buttonStyle(.borderedProminent)
        .disabled(request.url.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
        .keyboardShortcut(.return, modifiers: .command)
    }

    private func autoParseCurlIfPasted(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("curl") else { return }
        let afterCurl = trimmed.dropFirst(4)
        guard afterCurl.first == " " || afterCurl.first == "\n" || afterCurl.first == "\\" else { return }
        guard let parsed = try? CURLParser.parse(trimmed) else { return }

        var newReq = request
        newReq.method = parsed.method
        newReq.url = parsed.url
        newReq.headers = parsed.headers
        newReq.body = parsed.body
        newReq.auth = parsed.auth
        newReq.queryParams = parsed.queryParams
        newReq.updatedAt = Date()
        request = newReq
    }
}

#Preview("URLBarView") {
    @Previewable @State var request = KoalaRequest.empty

    return URLBarView(
        request: $request,
        isSending: false,
        onSend: {}
    )
    .environment(AppState())
    .frame(width: 700)
    .padding()
}
