import SwiftUI

struct MethodPickerView: View {
    @Binding var method: HTTPMethodValue

    @State private var showCustomSheet = false
    @State private var customMethodDraft = ""
    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker.toggle()
        } label: {
            methodLabel
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            methodPickerPopover
        }
        .sheet(isPresented: $showCustomSheet) {
            CustomMethodSheet(draft: $customMethodDraft) { submitted in
                if !submitted.isEmpty {
                    method = .custom(submitted.uppercased())
                }
            }
        }
    }

    private var methodPickerPopover: some View {
        VStack(spacing: 2) {
            ForEach(HTTPMethod.allCases) { m in
                pickerButton(
                    label: m.displayName,
                    color: m.color,
                    secondary: nil,
                    isCurrent: { if case .standard(let c) = method, c == m { return true }; return false }()
                ) {
                    method = .standard(m)
                    showPicker = false
                }
            }
            Divider().padding(.vertical, 2)
            pickerButton(
                label: "WS",
                color: .cyan,
                secondary: "WebSocket",
                isCurrent: method == .websocket
            ) {
                method = .websocket
                showPicker = false
            }
            pickerButton(
                label: "SSE",
                color: Color(red: 0.6, green: 0.3, blue: 0.85),
                secondary: "Server-Sent Events",
                isCurrent: method == .sse
            ) {
                method = .sse
                showPicker = false
            }
            Divider().padding(.vertical, 2)
            Button {
                showPicker = false
                if case .custom(let existing) = method {
                    customMethodDraft = existing
                } else {
                    customMethodDraft = ""
                }
                showCustomSheet = true
            } label: {
                HStack {
                    Text("Custom...")
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(width: 200)
    }

    private func pickerButton(
        label: String,
        color: Color,
        secondary: String?,
        isCurrent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundStyle(isCurrent ? Color.white : color)
                    .fontWeight(.semibold)
                if let secondary {
                    Text(secondary)
                        .foregroundStyle(isCurrent ? Color.white.opacity(0.85) : .secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isCurrent ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var methodLabel: some View {
        Text(method.displayName)
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .foregroundStyle(method.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(method.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

}

// MARK: - CustomMethodSheet

private struct CustomMethodSheet: View {
    @Binding var draft: String
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom HTTP Method")
                .font(.headline)

            TextField("e.g. PURGE, COPY, PROPFIND", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit() }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Apply") { submit() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func submit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        onSubmit(trimmed)
        dismiss()
    }
}

// MARK: - Preview

#Preview("MethodPickerView") {
    @Previewable @State var method: HTTPMethodValue = .standard(.get)

    return VStack(spacing: 20) {
        HStack(spacing: 12) {
            MethodPickerView(method: $method)
            Text("Selected: \(method.displayName)")
                .foregroundStyle(.secondary)
        }

        HStack(spacing: 8) {
            ForEach(HTTPMethod.allCases) { m in
                MethodPickerView(method: .constant(.standard(m)))
            }
        }
    }
    .padding(24)
}
