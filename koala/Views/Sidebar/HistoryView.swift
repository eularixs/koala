import SwiftUI

struct HistoryView: View {
    @Environment(WorkspaceState.self) private var workspaceState
    @Environment(HistoryService.self) private var historyService
    @State private var filterURL: String = ""
    @State private var filterMethod: String = "All"

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if filteredEntries.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredEntries) { entry in
                        HistoryRowView(entry: entry)
                            .onTapGesture { workspaceState.openRequest(entry.requestSnapshot) }
                            .contextMenu { rowContextMenu(entry: entry) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .background(Color.clear)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) { historyService.clear() } label: {
                    Label("Clear History", systemImage: "trash")
                }
                .disabled(historyService.entries.isEmpty)
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Filter URL", text: $filterURL)
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !filterURL.isEmpty {
                    Button { filterURL = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)

            HStack(spacing: 8) {
                methodPicker
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 8)
    }

    private var methodPicker: some View {
        Picker("Method", selection: $filterMethod) {
            Text("All").tag("All")
            ForEach(HTTPMethod.allCases) { m in
                Text(m.rawValue).tag(m.rawValue)
            }
        }
        .pickerStyle(.menu)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No History")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func rowContextMenu(entry: HistoryEntry) -> some View {
        Button("Replay") { workspaceState.openRequest(entry.requestSnapshot) }
        Divider()
        Button("Delete", role: .destructive) { historyService.remove(entry.id) }
    }

    private var filteredEntries: [HistoryEntry] {
        historyService.entries.filter { entry in
            let urlMatch = filterURL.isEmpty || entry.requestSnapshot.url.localizedCaseInsensitiveContains(filterURL)
            let methodMatch = filterMethod == "All" || entry.requestSnapshot.method.rawValue == filterMethod
            return urlMatch && methodMatch
        }
    }
}

// MARK: - HistoryRowView

private struct HistoryRowView: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 8) {
            if let response = entry.responseSnapshot {
                StatusBadgeView(statusCode: response.statusCode, showText: false)
            } else {
                Text("—")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.2), in: Capsule())
            }
            Text(entry.requestSnapshot.method.rawValue)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(entry.requestSnapshot.method.color)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(entry.requestSnapshot.method.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            Text(middleTruncated(entry.requestSnapshot.url))
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(relativeTime(entry.sentAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func middleTruncated(_ url: String) -> String {
        let limit = 60
        guard url.count > limit else { return url }
        let half = limit / 2
        let start = url.prefix(half)
        let end = url.suffix(half)
        return "\(start)…\(end)"
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
