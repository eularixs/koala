import SwiftUI

// MARK: - CollectionEditorSheet

/// TablePlus-style create/edit form for a Collection.
struct CollectionEditorSheet: View {
    /// nil = create mode. Non-nil = edit mode.
    let editing: KoalaCollection?
    let onSave: (_ name: String, _ colorHex: String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var colorHex: String? = nil

    private let palette: [String] = [
        "#FF6B6B", "#FFA94D", "#FFD43B", "#51CF66",
        "#22B8CF", "#4DABF7", "#9775FA", "#F783AC"
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
        }
        .frame(width: 480, height: 320)
        .onAppear {
            name = editing?.name ?? ""
            colorHex = editing?.color
        }
    }

    private var header: some View {
        HStack {
            Text(editing == nil ? "New Collection" : "Edit Collection")
                .font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Save") {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                onSave(trimmed, colorHex)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("General")
            groupedCard {
                row("Name") {
                    TextField("Collection name", text: $name)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                }
            }

            sectionTitle("Color")
            groupedCard {
                row("Color") {
                    HStack(spacing: 6) {
                        ForEach(palette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex) ?? .gray)
                                .frame(width: 18, height: 18)
                                .overlay {
                                    if colorHex == hex {
                                        Circle().stroke(Color.primary, lineWidth: 2)
                                    }
                                }
                                .onTapGesture { colorHex = hex }
                        }
                        Button {
                            colorHex = nil
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                    }
                }
            }

            Spacer()
        }
        .padding(16)
    }

    @ViewBuilder
    private func sectionTitle(_ s: String) -> some View {
        Text(s)
            .font(.headline)
    }

    @ViewBuilder
    private func groupedCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func row<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 80, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
