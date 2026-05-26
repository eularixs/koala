import SwiftUI

// MARK: - RequestTabsView

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
            // 1 px bottom divider under the tab bar
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
            tabContent
        }
        .background(
            Button("") {
                if let id = workspaceState.activeTabId {
                    workspaceState.closeTab(id)
                }
            }
            .keyboardShortcut("w", modifiers: .command)
            .hidden()
        )
    }

    // MARK: - Tab Strip

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(workspaceState.openTabs) { tab in
                    FinderTabView(
                        tab: tab,
                        isActive: tab.id == workspaceState.activeTabId,
                        onSelect: { workspaceState.activeTabId = tab.id },
                        onClose: { workspaceState.closeTab(tab.id) }
                    )
                }
                newTabButton
                Spacer(minLength: 0)
            }
        }
        .frame(height: 34)
        .background(.bar)
    }

    // MARK: - New Tab Button

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
        .buttonStyle(HoverButtonStyle())
        .help("New Request (⌘T)")
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

    private let minTabWidth: CGFloat = 120
    private let maxTabWidth: CGFloat = 200

    var body: some View {
        ZStack(alignment: .bottom) {
            // Active tab gets a slightly lighter fill
            if isActive {
                Rectangle()
                    .fill(Color(nsColor: .controlBackgroundColor))
            } else if isHovering {
                Rectangle()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }

            // Tab content row
            HStack(spacing: 4) {
                methodBadge
                tabLabel
                closeButton
            }
            .padding(.horizontal, 8)
            .frame(minWidth: minTabWidth, maxWidth: maxTabWidth, maxHeight: .infinity)

            // Right-side separator (only between tabs — not after last active)
            if !isActive {
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1)
                }
            }
        }
        .frame(minWidth: minTabWidth, maxWidth: maxTabWidth)
        .frame(height: 34)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
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
        HStack(spacing: 3) {
            Text(tab.request.name.isEmpty ? "Untitled" : tab.request.name)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if tab.hasUnsavedChanges {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
            }
        }
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

// MARK: - HoverButtonStyle

private struct HoverButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovering ? Color(nsColor: .controlBackgroundColor) : Color.clear)
            )
            .onHover { isHovering = $0 }
    }
}
