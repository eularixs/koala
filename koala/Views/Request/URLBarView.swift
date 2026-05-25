import SwiftUI

struct URLBarView: View {
    @Binding var request: KoalaRequest
    let isSending: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            MethodPickerView(method: $request.method)

            TextField("https://api.example.com/endpoint", text: $request.url)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity)
                .onChange(of: request.url) { _, newValue in
                    autoParseCurlIfPasted(newValue)
                }

            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
    .frame(width: 700)
    .padding()
}
