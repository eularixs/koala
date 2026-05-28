import SwiftUI

/// Two-pane JavaScript editor for pre-request and post-response (test) scripts.
struct ScriptsEditorView: View {
    @Binding var request: KoalaRequest

    var body: some View {
        HSplitView {
            paneView(
                title: "Pre-request Script",
                help: "Runs before the request is sent. Mutate koala.request, koala.env, koala.globals.",
                example: preRequestExample,
                text: Binding(
                    get: { request.preRequestScript ?? "" },
                    set: { request.preRequestScript = $0.isEmpty ? nil : $0 }
                )
            )

            paneView(
                title: "Post-response / Tests",
                help: "Runs after the response is received. Use koala.test() and koala.expect() to assert.",
                example: testExample,
                text: Binding(
                    get: { request.testScript ?? "" },
                    set: { request.testScript = $0.isEmpty ? nil : $0 }
                )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func paneView(title: String, help: String, example: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DisclosureGroup("Example") {
                    Text(example)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            CodeEditorView(text: text, language: "javascript", minHeight: 220)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(minWidth: 280)
    }

    private var preRequestExample: String {
        """
        // Set a header from an env var
        const token = koala.env.get('authToken');
        if (token) koala.request.setHeader('Authorization', 'Bearer ' + token);

        // Stash a timestamp for the test script
        koala.globals.set('requestStartedAt', Date.now().toString());
        """
    }

    private var testExample: String {
        """
        koala.test("status is 200", () => {
          koala.expect(koala.response.status).toBe(200);
        });

        koala.test("body has id", () => {
          const json = koala.response.json();
          koala.expect(json.id).toBeTruthy();
        });

        // Persist a value extracted from response
        const json = koala.response.json();
        if (json && json.token) koala.env.set('authToken', json.token);
        """
    }
}

#Preview("ScriptsEditorView") {
    @Previewable @State var req = KoalaRequest(
        preRequestScript: "console.log('hello')",
        testScript: "koala.test('ok', () => true);"
    )
    return ScriptsEditorView(request: $req)
        .frame(width: 900, height: 500)
}
