import SwiftUI

// MARK: - RequestTabsView

struct RequestTabsView<Content: View>: View {
    @Environment(WorkspaceState.self) private var workspaceState
    let content: (Binding<RequestTab>) -> Content

    @State private var pendingCloseTabId: UUID? = nil

    init(@ViewBuilder content: @escaping (Binding<RequestTab>) -> Content) {
        self.content = content
    }

    var body: some View {
        @Bindable var state = workspaceState
        VStack(spacing: 0) {
            if workspaceState.openTabs.count > 1 {
                // 1 px top divider above tab bar
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
                tabStrip
                // 1 px bottom divider under tab bar
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
            }
            tabContent
        }
        .background(
            ZStack {
                Button("") {
                    if let id = workspaceState.activeTabId {
                        requestClose(tabId: id)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .hidden()

                Button("") {
                    workspaceState.openNew()
                }
                .keyboardShortcut("t", modifiers: .command)
                .hidden()

                Button("") { jumpToTab(index: 0) }
                    .keyboardShortcut("1", modifiers: .command).hidden()
                Button("") { jumpToTab(index: 1) }
                    .keyboardShortcut("2", modifiers: .command).hidden()
                Button("") { jumpToTab(index: 2) }
                    .keyboardShortcut("3", modifiers: .command).hidden()
                Button("") { jumpToTab(index: 3) }
                    .keyboardShortcut("4", modifiers: .command).hidden()
                Button("") { jumpToTab(index: 4) }
                    .keyboardShortcut("5", modifiers: .command).hidden()
                Button("") { jumpToTab(index: 5) }
                    .keyboardShortcut("6", modifiers: .command).hidden()
                Button("") { jumpToTab(index: 6) }
                    .keyboardShortcut("7", modifiers: .command).hidden()
                Button("") { jumpToTab(index: 7) }
                    .keyboardShortcut("8", modifiers: .command).hidden()
                Button("") { jumpToTab(index: 8) }
                    .keyboardShortcut("9", modifiers: .command).hidden()

                Button("") {
                    if let last = workspaceState.openTabs.last {
                        workspaceState.activeTabId = last.id
                    }
                }
                .keyboardShortcut("0", modifiers: .command)
                .hidden()

                Button("") { cycleTab(offset: 1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift]).hidden()
                Button("") { cycleTab(offset: -1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift]).hidden()
            }
        )
        .confirmationDialog(
            "Discard unsaved changes?",
            isPresented: Binding(
                get: { pendingCloseTabId != nil },
                set: { if !$0 { pendingCloseTabId = nil } }
            ),
            presenting: pendingCloseTabId
        ) { id in
            Button("Discard Changes", role: .destructive) {
                workspaceState.closeTab(id)
                pendingCloseTabId = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCloseTabId = nil
            }
        } message: { _ in
            Text("This request has unsaved changes. They will be lost if you close the tab.")
        }
    }

    private func jumpToTab(index: Int) {
        guard index >= 0, index < workspaceState.openTabs.count else { return }
        workspaceState.activeTabId = workspaceState.openTabs[index].id
    }

    private func cycleTab(offset: Int) {
        let count = workspaceState.openTabs.count
        guard count > 0 else { return }
        let currentIdx = workspaceState.openTabs.firstIndex(where: { $0.id == workspaceState.activeTabId }) ?? 0
        let nextIdx = ((currentIdx + offset) % count + count) % count
        workspaceState.activeTabId = workspaceState.openTabs[nextIdx].id
    }

    private func requestClose(tabId: UUID) {
        guard let tab = workspaceState.openTabs.first(where: { $0.id == tabId }) else { return }
        if tab.isDirty {
            pendingCloseTabId = tabId
        } else {
            workspaceState.closeTab(tabId)
        }
    }

    // MARK: - Tab Strip

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(workspaceState.openTabs) { tab in
                FinderTabView(
                    tab: tab,
                    isActive: tab.id == workspaceState.activeTabId,
                    onSelect: { workspaceState.activeTabId = tab.id },
                    onClose: { requestClose(tabId: tab.id) }
                )
                .frame(maxWidth: .infinity)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.85).combined(with: .opacity),
                    removal: .opacity.combined(with: .scale(scale: 0.9))
                ))
            }
            newTabButton
            if workspaceState.openTabs.isEmpty {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(.bar)
        .animation(.spring(duration: 0.28, bounce: 0.18), value: workspaceState.openTabs.count)
    }

    // MARK: - New Tab Button

    private var newTabButton: some View {
        NewTabPlusButton(action: { workspaceState.openNew() })
            .padding(.horizontal, 4)
    }

    // MARK: - Tab Content

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

// MARK: - FinderTabView

private struct FinderTabView: View {
    let tab: RequestTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack {
            rowBackground
                .contentShape(Rectangle())
                .onTapGesture { onSelect() }

            HStack(spacing: 4) {
                methodBadge
                tabLabel
                if tab.isDirty {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 28)
            .allowsHitTesting(false)

            HStack {
                if isHovering || isActive {
                    closeButton
                        .padding(.leading, 6)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .overlay(alignment: .trailing) {
            if !isActive {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
            }
        }
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isActive {
            Rectangle().fill(Color(nsColor: .controlBackgroundColor))
        } else if isHovering {
            Rectangle().fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        } else {
            Color.clear
        }
    }

    private var methodBadge: some View {
        Text(tab.request.method.rawValue)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(tab.request.method.color, in: RoundedRectangle(cornerRadius: 3))
    }

    private var tabLabel: some View {
        Text(tab.request.name.isEmpty ? "Untitled" : tab.request.name)
            .font(.system(size: 12, weight: isActive ? .semibold : .regular))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isHovering || isActive ? 1 : 0)
    }
}

// MARK: - NewTabPlusButton

private struct NewTabPlusButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovering ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New Request (⌘T)")
        .onHover { isHovering = $0 }
    }
}
