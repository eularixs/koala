import SwiftUI

struct EnvironmentListView: View {
    @Environment(AppState.self) private var appState
    @State private var editingEnvId: UUID? = nil
    @State private var renameText: String = ""
    @State private var sheetTarget: SheetTarget? = nil

    private enum SheetTarget: Identifiable {
        case environment(UUID)
        case newEnvironment
        case globalVariables

        var id: String {
            switch self {
            case .environment(let id): return id.uuidString
            case .newEnvironment:      return "new-env"
            case .globalVariables:     return "globals"
            }
        }
    }

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            sectionHeader
            Divider()
            List {
                globalVariablesRow
                ForEach($state.environments) { $env in
                    environmentRow(env: env, binding: $env)
                }
                .onDelete { offsets in deleteEnvironments(at: offsets) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .background(Color.clear)
        .sheet(item: $sheetTarget) { target in
            sheetContent(for: target)
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text("Environments")
                .font(.headline)
                .padding(.leading, 12)
            Spacer()
            Button {
                sheetTarget = .newEnvironment
            } label: {
                Label("New", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 8)
    }

    private var globalVariablesRow: some View {
        Button {
            sheetTarget = .globalVariables
        } label: {
            HStack {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                Text("Global Variables")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func environmentRow(env: KoalaEnvironment, binding: Binding<KoalaEnvironment>) -> some View {
        HStack {
            if editingEnvId == env.id {
                TextField("Name", text: $renameText, onCommit: {
                    commitRename(for: env.id)
                })
                .textFieldStyle(.roundedBorder)
                .onExitCommand { editingEnvId = nil }
            } else {
                HStack {
                    Circle()
                        .fill(envDotColor(for: env))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(appState.selectedEnvironmentId == env.id ? 0.6 : 0), lineWidth: 1.5)
                        )
                    Text(env.name)
                        .foregroundStyle(appState.selectedEnvironmentId == env.id ? .primary : .secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.selectedEnvironmentId = env.id
                    sheetTarget = .environment(env.id)
                }
                .onTapGesture(count: 2) {
                    editingEnvId = env.id
                    renameText = env.name
                }
            }
        }
        .contextMenu {
            Button("Rename") {
                editingEnvId = env.id
                renameText = env.name
            }
            Button("Edit") { sheetTarget = .environment(env.id) }
            Divider()
            Button("Delete", role: .destructive) {
                appState.environments.removeAll(where: { $0.id == env.id })
                if appState.selectedEnvironmentId == env.id {
                    appState.selectedEnvironmentId = nil
                }
                appState.saveToDisk()
            }
        }
        .padding(.vertical, 2)
    }

    private func envDotColor(for env: KoalaEnvironment) -> Color {
        if let hex = env.color, let c = Color(hex: hex) { return c }
        return Color.secondary.opacity(0.4)
    }

    private func commitRename(for id: UUID) {
        guard let idx = appState.environments.firstIndex(where: { $0.id == id }) else {
            editingEnvId = nil
            return
        }
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            appState.environments[idx].name = trimmed
            appState.saveToDisk()
        }
        editingEnvId = nil
    }

    private func deleteEnvironments(at offsets: IndexSet) {
        let toDelete = offsets.map { appState.environments[$0].id }
        appState.environments.remove(atOffsets: offsets)
        for id in toDelete where appState.selectedEnvironmentId == id {
            appState.selectedEnvironmentId = nil
        }
        appState.saveToDisk()
    }

    @ViewBuilder
    private func sheetContent(for target: SheetTarget) -> some View {
        @Bindable var state = appState
        switch target {
        case .environment(let id):
            if let env = appState.environments.first(where: { $0.id == id }) {
                EnvironmentEditorView(environment: env, isNew: false) { updated in
                    if let idx = appState.environments.firstIndex(where: { $0.id == id }) {
                        appState.environments[idx] = updated
                        appState.saveToDisk()
                    }
                }
            }
        case .newEnvironment:
            EnvironmentEditorView(environment: KoalaEnvironment(), isNew: true) { newEnv in
                appState.environments.append(newEnv)
                appState.saveToDisk()
            }
        case .globalVariables:
            GlobalVariablesEditorSheet(items: $state.globalVariables)
        }
    }
}

// MARK: - GlobalVariablesEditorSheet

private struct GlobalVariablesEditorSheet: View {
    @Binding var items: [KeyValuePair]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Global Variables")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            KeyValueEditorView(items: $items, showSecretToggle: true)
                .padding(12)
            Spacer()
        }
        .frame(minWidth: 520, minHeight: 400)
    }
}
