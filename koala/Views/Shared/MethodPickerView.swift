import SwiftUI

struct MethodPickerView: View {
    @Binding var method: HTTPMethodValue

    @State private var showCustomSheet = false
    @State private var customMethodDraft = ""

    var body: some View {
        Menu {
            standardMethodItems
            Divider()
            customMethodItem
        } label: {
            methodLabel
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .sheet(isPresented: $showCustomSheet) {
            CustomMethodSheet(draft: $customMethodDraft) { submitted in
                if !submitted.isEmpty {
                    method = .custom(submitted.uppercased())
                }
            }
        }
    }

    private var methodLabel: some View {
        HStack(spacing: 4) {
            Text(method.displayName)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(method.color)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(method.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var standardMethodItems: some View {
        ForEach(HTTPMethod.allCases) { m in
            Button {
                method = .standard(m)
            } label: {
                HStack {
                    Text(m.displayName)
                        .foregroundStyle(m.color)
                        .fontWeight(.semibold)
                    if case .standard(let current) = method, current == m {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    private var customMethodItem: some View {
        Button("Custom...") {
            if case .custom(let existing) = method {
                customMethodDraft = existing
            } else {
                customMethodDraft = ""
            }
            showCustomSheet = true
        }
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
