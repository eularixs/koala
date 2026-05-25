import SwiftUI

struct ProjectSwitcherView: View {
    @Environment(AppState.self) private var appState
    @State private var showNewProjectSheet = false
    @State private var showManageSheet = false

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                projectItems
                Divider()
                Button("New Project...") { showNewProjectSheet = true }
                Button("Manage Projects...") { showManageSheet = true }
            } label: {
                menuLabel
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .sheet(isPresented: $showNewProjectSheet) {
            ProjectEditorView(mode: .create)
                .environment(appState)
        }
        .sheet(isPresented: $showManageSheet) {
            ProjectEditorView(mode: .manage)
                .environment(appState)
        }
    }

    // MARK: - Menu Label

    private var menuLabel: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(activeColor)
                .frame(width: 8, height: 8)
            Text(appState.activeProject?.name ?? "No Project")
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Menu Items

    @ViewBuilder
    private var projectItems: some View {
        ForEach(appState.projects) { project in
            Button {
                appState.switchProject(to: project.id)
            } label: {
                HStack {
                    Circle()
                        .fill(Color(hex: project.color) ?? .accentColor)
                        .frame(width: 8, height: 8)
                    Text(project.name)
                    if appState.activeProjectId == project.id {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var activeColor: Color {
        Color(hex: appState.activeProject?.color) ?? .accentColor
    }
}

