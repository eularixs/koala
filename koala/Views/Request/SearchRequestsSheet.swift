import SwiftUI

// MARK: - SearchRequestsSheet

/// Spotlight-style request picker. Filter by name + URL across active project's collections.
struct SearchRequestsSheet: View {
    let onPick: (KoalaRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var query: String = ""

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            results
        }
        .frame(width: 540, height: 420)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search by name or endpoint…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button("Esc") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        let matches = filteredRequests
        if matches.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(matches, id: \.request.id) { hit in
                        row(hit)
                        Divider().padding(.leading, 56)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: query.isEmpty ? "doc.text.magnifyingglass" : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "Type to search across requests" : "No matches")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ hit: SearchHit) -> some View {
        Button {
            onPick(hit.request)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                methodBadge(hit.request.method)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.request.name.isEmpty ? "Untitled" : hit.request.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !hit.request.url.isEmpty {
                        Text(hit.request.url)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if !hit.breadcrumb.isEmpty {
                        Text(hit.breadcrumb)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func methodBadge(_ method: HTTPMethodValue) -> some View {
        Text(method.rawValue)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(method.color, in: RoundedRectangle(cornerRadius: 3))
            .frame(width: 50, alignment: .leading)
    }

    // MARK: - Filtering

    private struct SearchHit {
        let request: KoalaRequest
        let breadcrumb: String
    }

    private var filteredRequests: [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        var hits: [SearchHit] = []
        for col in appState.collections {
            collect(items: col.items, trail: [col.name], into: &hits)
        }
        guard !needle.isEmpty else {
            return hits
        }
        return hits.filter { hit in
            hit.request.name.lowercased().contains(needle)
                || hit.request.url.lowercased().contains(needle)
        }
    }

    private func collect(items: [CollectionItem], trail: [String], into hits: inout [SearchHit]) {
        for item in items {
            switch item {
            case .request(let r):
                hits.append(SearchHit(request: r, breadcrumb: trail.joined(separator: " / ")))
            case .folder(let f):
                collect(items: f.items, trail: trail + [f.name], into: &hits)
            }
        }
    }
}
