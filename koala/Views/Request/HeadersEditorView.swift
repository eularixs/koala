import SwiftUI

struct HeadersEditorView: View {
    @Binding var request: KoalaRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Headers")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            KeyValueEditorView(
                items: $request.headers,
                showDescription: true
            )
        }
        .padding(12)
    }
}

#Preview("HeadersEditorView") {
    @Previewable @State var request = KoalaRequest(
        headers: [
            KeyValuePair(key: "Content-Type", value: "application/json", isEnabled: true),
            KeyValuePair(key: "Authorization", value: "Bearer token", isEnabled: true, isSecret: true),
        ]
    )

    return HeadersEditorView(request: $request)
        .frame(width: 600)
        .padding()
}
