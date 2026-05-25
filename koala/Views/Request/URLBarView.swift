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

            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Group {
                if isSending {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    Text("Send")
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(request.url.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
        .keyboardShortcut(.return, modifiers: .command)
        .fixedSize()
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
