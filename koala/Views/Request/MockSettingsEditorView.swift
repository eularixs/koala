import SwiftUI

// MARK: - MockSettingsEditorView

struct MockSettingsEditorView: View {
    @Binding var request: KoalaRequest
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            enableToggle
            if request.isMock {
                infoBanner
                mockURLField
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Enable Toggle

    private var enableToggle: some View {
        Toggle("Enable Mock for this request", isOn: $request.isMock)
            .toggleStyle(.switch)
    }

    // MARK: - Info Banner

    private var infoBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("When enabled, requests are served from the mocked endpoint instead of the live URL.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Mock URL Display

    private var mockURLField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mock URL")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(derivedMockURL)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - URL Derivation

    private var derivedMockURL: String {
        let baseURL = mockBaseURL
        let slug = appState.activeProject?.slug ?? "project"
        let path = normalizedPath(from: request.url)
        return "\(baseURL)/\(slug)\(path)"
    }

    private var mockBaseURL: String {
        guard let env = appState.environments.first(where: { $0.name == "Mock Cloud" }),
              let variable = env.variables.first(where: { $0.key == "MOCK_BASE_URL" && $0.isEnabled }),
              !variable.value.isEmpty else {
            return "https://koala-mock.vercel.app"
        }
        return variable.value
    }

    private func normalizedPath(from url: String) -> String {
        guard let parsed = URL(string: url), !parsed.path.isEmpty else { return "/" }
        return parsed.path.hasPrefix("/") ? parsed.path : "/\(parsed.path)"
    }
}

// MARK: - Preview

#Preview("MockSettingsEditorView") {
    @Previewable @State var request = KoalaRequest(
        url: "https://api.example.com/users/123",
        isMock: true
    )
    MockSettingsEditorView(request: $request)
        .environment(AppState())
        .frame(width: 600)
        .padding()
}
