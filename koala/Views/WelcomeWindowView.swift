import SwiftUI
import UniformTypeIdentifiers

struct WelcomeWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportExportService.self) private var importExportService

    let onPicked: () -> Void

    @State private var showCreateSheet = false
    @State private var newProjectName = ""
    @State private var newProjectSlug = ""
    @State private var newProjectColor: String? = nil

    @State private var showImporter = false
    @State private var importError: String? = nil
    @State private var showImportError = false

    @State private var search = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 280)
                .background(.regularMaterial)
            Divider()
            projectsList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 880, minHeight: 560)
        .sheet(isPresented: $showCreateSheet) { createSheet }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, .data, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Import Error", isPresented: $showImportError, presenting: importError) { _ in
            Button("OK") {}
        } message: { Text($0) }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer().frame(height: 24)

            VStack(alignment: .center, spacing: 12) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Koala")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                Text("Native macOS API client")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Spacer()

            VStack(spacing: 10) {
                Button(action: openCreate) {
                    Label("Create Project", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: { showImporter = true }) {
                    Label("Import from Other App", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer().frame(height: 16)
        }
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Projects list

    private var projectsList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Your Projects")
                    .font(.title2.weight(.semibold))
                Spacer()
                TextField("", text: $search, prompt: Text("Search projects..."))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)

            Divider()

            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                        ForEach(filtered) { project in
                            ProjectCard(project: project) {
                                openProject(project)
                            } onDelete: {
                                appState.deleteProject(project.id)
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
    }

    private var filtered: [Project] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return appState.projects }
        return appState.projects.filter {
            $0.name.lowercased().contains(needle) || $0.slug.lowercased().contains(needle)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No projects yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Click \"Create Project\" to get started.")
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Create sheet

    private var createSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project").font(.title2.weight(.semibold))

            Form {
                LabeledContent("Name") {
                    TextField("", text: $newProjectName, prompt: Text("e.g. Eularix"))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: newProjectName) { _, new in
                            newProjectSlug = Project.deriveSlug(from: new)
                        }
                }
                LabeledContent("Slug") {
                    TextField("", text: $newProjectSlug, prompt: Text("eularix"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Color") {
                    colorPicker
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    showCreateSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                Button("Create") {
                    createProject()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var colorPicker: some View {
        HStack(spacing: 8) {
            ForEach(["#FF6B6B", "#FFA94D", "#FFD43B", "#51CF66", "#22B8CF", "#4DABF7", "#9775FA", "#F783AC"], id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex) ?? .gray)
                    .frame(width: 22, height: 22)
                    .overlay {
                        if newProjectColor == hex {
                            Circle().stroke(Color.primary, lineWidth: 2)
                        }
                    }
                    .onTapGesture { newProjectColor = hex }
            }
            Button {
                newProjectColor = nil
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Clear color")
        }
    }

    // MARK: - Actions

    private func openCreate() {
        newProjectName = ""
        newProjectSlug = ""
        newProjectColor = nil
        showCreateSheet = true
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var project = appState.createProject(name: name)
        if !newProjectSlug.isEmpty {
            appState.setSlug(newProjectSlug, for: project.id)
            project.slug = newProjectSlug
        }
        if let c = newProjectColor {
            appState.setColor(c, for: project.id)
        }
        appState.switchProject(to: project.id)
        showCreateSheet = false
        onPicked()
    }

    private func openProject(_ project: Project) {
        appState.switchProject(to: project.id)
        onPicked()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            importError = err.localizedDescription
            showImportError = true
        case .success(let urls):
            guard let url = urls.first else { return }
            let project = appState.createProject(name: url.deletingPathExtension().lastPathComponent)
            appState.switchProject(to: project.id)
            do {
                try importExportService.importFile(at: url, into: project.id, appState: appState)
                onPicked()
            } catch {
                importError = error.localizedDescription
                showImportError = true
            }
        }
    }
}

// MARK: - ProjectCard

private struct ProjectCard: View {
    let project: Project
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var confirmDelete = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle()
                        .fill(Color(hex: project.color ?? "") ?? .secondary)
                        .frame(width: 12, height: 12)
                    Spacer()
                    Menu {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }

                Text(project.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(project.slug)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Text("Updated " + relativeDate(project.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(hovering ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .alert("Delete Project?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(project.name)\" and all its data will be permanently removed.")
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
