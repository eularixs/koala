import SwiftUI

struct RequestTabsView<Content: View>: View {
    @Environment(WorkspaceState.self) private var workspaceState
    let content: (Binding<RequestTab>) -> Content

    init(@ViewBuilder content: @escaping (Binding<RequestTab>) -> Content) {
        self.content = content
    }

    var body: some View {
        @Bindable var state = workspaceState
        VStack(spacing: 0) {
            tabStrip
            Divider()
            tabContent
        }
        .onKeyPress(KeyEquivalent("w"), action: {
            if let id = workspaceState.activeTabId {
                workspaceState.closeTab(id)
                return .handled
            }
            return .ignored
        })
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(workspaceState.openTabs) { tab in
                    TabPillView(
                        tab: tab,
                        isActive: tab.id == workspaceState.activeTabId,
                        onSelect: { workspaceState.activeTabId = tab.id },
                        onClose: { workspaceState.closeTab(tab.id) }
                    )
                }
                newTabButton
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var newTabButton: some View {
        Button {
            workspaceState.openNew()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New Request (⌘T)")
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var tabContent: some View {
        @Bindable var state = workspaceState
        if workspaceState.openTabs.isEmpty {
            emptyState
        } else if let idx = workspaceState.openTabs.firstIndex(where: { $0.id == workspaceState.activeTabId }) {
            content($state.openTabs[idx])
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "paperplane")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Open a request from the sidebar or click +")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - TabPillView

private struct TabPillView: View {
    let tab: RequestTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tab.request.method.rawValue)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(tab.request.method.color, in: RoundedRectangle(cornerRadius: 3))

            Text(tab.request.name.isEmpty ? "Untitled" : tab.request.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .leading)
                .foregroundStyle(isActive ? .primary : .secondary)

            if tab.hasUnsavedChanges {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 16, height: 16)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color(nsColor: .controlBackgroundColor) : .clear)
                .shadow(color: isActive ? .black.opacity(0.1) : .clear, radius: 1, y: 1)
        )
        .onTapGesture(perform: onSelect)
        .contentShape(Rectangle())
    }
}
