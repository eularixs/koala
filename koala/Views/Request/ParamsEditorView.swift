import SwiftUI

struct ParamsEditorView: View {
    @Binding var request: KoalaRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Query Parameters")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            KeyValueEditorView(items: $request.queryParams)
        }
        .padding(12)
    }
}

#Preview("ParamsEditorView") {
    @Previewable @State var request = KoalaRequest(
        queryParams: [
            KeyValuePair(key: "page", value: "1", isEnabled: true),
            KeyValuePair(key: "limit", value: "20", isEnabled: true),
        ]
    )

    return ParamsEditorView(request: $request)
        .frame(width: 600)
        .padding()
}
