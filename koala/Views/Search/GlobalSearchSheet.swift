import SwiftUI

// MARK: - GlobalSearchSheet
//
// Spotlight-style cross-project search. Loads collections from every project
// (lazy, via PersistenceService) on appear so search isn't limited to the
// active project's hydrated slice in AppState.
//
// Pro gate: when `LicenseService` is injected into the environment and
// `isPro == false`, an upsell view is shown instead of the search field.
// If the env value is absent, search is allowed (so this view builds and
// runs standalone before the License agent wires the service into the app).

struct GlobalSearchSheet: View {
    let onPick: (Project, KoalaRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(LicenseService.self) private var licenseService: LicenseService?

    @State private var query: String = ""
    @State private var projectCollections: [UUID: [KoalaCollection]] = [:]
    @State private var loaded: Bool = false

    private let persistence = PersistenceService()

    var body: some View {
        Group {
            if let lic = licenseService, lic.isPro == false {
                proGate
            } else {
                searchUI
            }
        }
        .frame(width: 640, height: 520)
        .task {
            guard !loaded else { return }
            loadAllProjectCollections()
            loaded = true
        }
    }

    // MARK: - Pro Gate

    @Environment(\.openSettings) private var openSettings

    private var proGate: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Global search is a Pro feature")
                .font(.title3.weight(.semibold))
            Text("Search requests across every project in your workspace.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 10) {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Upgrade to Pro") {
                    openSettings()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Search UI

    private var searchUI: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            results
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search across all projects…", text: $query)
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
            Text(query.isEmpty ? "Type to search across every project" : "No matches")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ hit: SearchHit) -> some View {
        Button {
            onPick(hit.project, hit.request)
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

    // MARK: - Load

    private func loadAllProjectCollections() {
        var map: [UUID: [KoalaCollection]] = [:]
        for project in appState.projects {
            // Reuse already-hydrated slice for the active project if available.
            // For all others, hit disk directly (cheap, no AppState mutation).
            let cols = (try? persistence.loadCollections(forProject: project.id)) ?? []
            map[project.id] = cols
        }
        projectCollections = map
    }

    // MARK: - Filtering

    private struct SearchHit {
        let project: Project
        let request: KoalaRequest
        let breadcrumb: String
    }

    private var filteredRequests: [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        var hits: [SearchHit] = []
        for project in appState.projects {
            let cols = projectCollections[project.id] ?? []
            for col in cols {
                collect(items: col.items, project: project, trail: [project.name, col.name], into: &hits)
            }
        }
        guard !needle.isEmpty else {
            return hits
        }
        return hits.filter { hit in
            hit.request.name.lowercased().contains(needle)
                || hit.request.url.lowercased().contains(needle)
        }
    }

    private func collect(items: [CollectionItem], project: Project, trail: [String], into hits: inout [SearchHit]) {
        for item in items {
            switch item {
            case .request(let r):
                hits.append(SearchHit(project: project, request: r, breadcrumb: trail.joined(separator: " / ")))
            case .folder(let f):
                collect(items: f.items, project: project, trail: trail + [f.name], into: &hits)
            }
        }
    }
}
