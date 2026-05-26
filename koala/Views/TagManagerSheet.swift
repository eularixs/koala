import SwiftUI

// MARK: - TagManagerSheet

struct TagManagerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var editingTag: ProjectTag? = nil
    @State private var showEditor = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 460, height: 420)
        .sheet(isPresented: $showEditor) {
            TagEditorSheet(initial: editingTag) { tag in
                appState.upsertTag(tag)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Manage Tags").font(.headline)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(appState.tags) { tag in
                    row(tag)
                    Divider().padding(.leading, 56)
                }
                if appState.tags.isEmpty {
                    Text("No tags yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
        }
    }

    private func row(_ tag: ProjectTag) -> some View {
        HStack(spacing: 10) {
            if let col = Color(hex: tag.colorHex) {
                Text(tag.name.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(col, in: Capsule())
            }
            Spacer()
            Button {
                editingTag = tag
                showEditor = true
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            Button(role: .destructive) {
                appState.deleteTag(tag.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                editingTag = nil
                showEditor = true
            } label: {
                Label("New Tag", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - TagEditorSheet

struct TagEditorSheet: View {
    let initial: ProjectTag?
    let onSave: (ProjectTag) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var colorHex: String = "#22B8CF"

    private let palette: [String] = [
        "#FF6B6B", "#FFA94D", "#FFD43B", "#51CF66",
        "#22B8CF", "#4DABF7", "#9775FA", "#F783AC",
        "#868E96", "#15AABF", "#7950F2", "#FF8787"
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
        }
        .frame(width: 420, height: 280)
        .onAppear {
            name = initial?.name ?? ""
            colorHex = initial?.colorHex ?? palette[0]
        }
    }

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
            Spacer()
            Text(initial == nil ? "New Tag" : "Edit Tag")
                .font(.headline)
            Spacer()
            Button("Save") {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                let tag = ProjectTag(
                    id: initial?.id ?? UUID(),
                    name: trimmed,
                    colorHex: colorHex
                )
                onSave(tag)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Preview").font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                if let col = Color(hex: colorHex) {
                    Text((name.isEmpty ? "TAG" : name).uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(col, in: Capsule())
                }
                Spacer()
            }

            HStack {
                Text("Name").font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                TextField("Development", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(alignment: .top) {
                Text("Color").font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 6), spacing: 8) {
                    ForEach(palette, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex) ?? .gray)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().stroke(Color.primary, lineWidth: colorHex == hex ? 2 : 0)
                            )
                            .onTapGesture { colorHex = hex }
                    }
                }
            }

            Spacer()
        }
        .padding(16)
    }
}
