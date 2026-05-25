import SwiftUI

// MARK: - ProjectEditorMode

enum ProjectEditorMode {
    case create
    case manage
}

// MARK: - ProjectEditorView

struct ProjectEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let mode: ProjectEditorMode

    @State private var newName: String = ""
    @State private var newSlug: String = ""
    @State private var newColor: String = ""
    @State private var slugEdited: Bool = false
    @State private var projectToDelete: Project? = nil
    @State private var showDeleteConfirm = false

    var body: some View {
        Group {
            if mode == .create {
                createContent
            } else {
                manageContent
            }
        }
        .frame(minWidth: 360, minHeight: 280)
    }

    // MARK: Create Mode

    private var createContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Project")
                .font(.headline)
                .padding()

            Divider()

            Form {
                TextField("Name", text: $newName)
                    .onChange(of: newName) { _, val in
                        if !slugEdited {
                            newSlug = Project.deriveSlug(from: val)
                        }
                    }

                TextField("Slug", text: $newSlug)
                    .onChange(of: newSlug) { _, _ in slugEdited = true }
                    .font(.system(.body, design: .monospaced))

                TextField("Color (hex)", text: $newColor)
                    .font(.system(.body, design: .monospaced))
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create") { createProject() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
    }

    // MARK: Manage Mode

    private var manageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Manage Projects")
                .font(.headline)
                .padding()

            Divider()

            List(appState.projects) { project in
                ProjectRowView(project: project, onDelete: {
                    projectToDelete = project
                    showDeleteConfirm = true
                })
            }
            .listStyle(.plain)

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .confirmationDialog(
            "Delete \"\(projectToDelete?.name ?? "")\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let p = projectToDelete { appState.deleteProject(p.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All collections, environments, and history for this project will be permanently deleted.")
        }
    }

    // MARK: - Actions

    private func createProject() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var project = appState.createProject(name: name)
        let slug = newSlug.trimmingCharacters(in: .whitespaces)
        if !slug.isEmpty && slug != project.slug {
            appState.setSlug(slug, for: project.id)
        }
        appState.switchProject(to: project.id)
        appState.saveToDisk()
        dismiss()
    }
}

// MARK: - ProjectRowView

private struct ProjectRowView: View {
    @Environment(AppState.self) private var appState
    let project: Project
    let onDelete: () -> Void

    @State private var editingName: String = ""
    @State private var isEditing = false

    var body: some View {
        HStack(spacing: 8) {
            projectDot
            if isEditing {
                TextField("Name", text: $editingName, onCommit: commitRename)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(project.name)
                    .fontWeight(appState.activeProjectId == project.id ? .semibold : .regular)
            }
            Spacer()
            if appState.activeProjectId == project.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Button {
                editingName = project.name
                isEditing.toggle()
            } label: {
                Image(systemName: isEditing ? "checkmark" : "pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.8))
        }
        .padding(.vertical, 2)
    }

    private var projectDot: some View {
        Circle()
            .fill(Color(hex: project.color) ?? .accentColor)
            .frame(width: 8, height: 8)
    }

    private func commitRename() {
        let name = editingName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { appState.renameProject(project.id, to: name) }
        isEditing = false
        appState.saveToDisk()
    }
}

// MARK: - Color hex helper (internal — shared with ProjectSwitcherView)

extension Color {
    init?(hex: String?) {
        guard let hex, !hex.isEmpty else { return nil }
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        let r = Double((val >> 16) & 0xFF) / 255.0
        let g = Double((val >> 8) & 0xFF) / 255.0
        let b = Double(val & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
