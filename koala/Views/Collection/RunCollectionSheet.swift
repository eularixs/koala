import SwiftUI

/// Sheet that runs every request inside a collection sequentially and shows
/// per-request status, SLA highlight, test pass/fail, and snapshot diffs.
struct RunCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let collection: KoalaCollection

    @State private var runner = CollectionRunnerService()
    @State private var expandedDiffs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            resultsBody
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name).font(.headline)
                Text("Collection Runner").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            progressView
            runButton
            Button("Close") { dismiss() }
        }
        .padding(12)
    }

    @ViewBuilder
    private var progressView: some View {
        let total = runner.progress.total
        let current = runner.progress.current
        if total > 0 {
            HStack(spacing: 8) {
                ProgressView(value: Double(current), total: Double(max(total, 1)))
                    .frame(width: 120)
                Text("\(current)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var runButton: some View {
        switch runner.status {
        case .running:
            Button {
                runner.cancel()
            } label: {
                Label("Cancel", systemImage: "stop.circle")
            }
        default:
            Button {
                Task { await startRun() }
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    // MARK: - Results body

    private var resultsBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if runner.results.isEmpty && runner.status != .running {
                    emptyState
                } else {
                    ForEach(runner.results) { result in
                        resultRow(result)
                        Divider()
                    }
                    if runner.status == .running {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Running...").foregroundStyle(.secondary)
                        }
                        .padding(12)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Click Run to execute all requests in this collection.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(24)
    }

    @ViewBuilder
    private func resultRow(_ result: RequestRunResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                methodBadge(for: result.requestId)
                Text(result.requestName)
                    .font(.body)
                Spacer()
                statusBadge(result)
                durationLabel(result)
                testsBadge(result)
            }

            if let err = result.error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let diff = result.snapshotDiff {
                Button {
                    toggleDiff(result.id)
                } label: {
                    Label(
                        expandedDiffs.contains(result.id) ? "Hide diff" : "View diff",
                        systemImage: expandedDiffs.contains(result.id) ? "chevron.down" : "chevron.right"
                    )
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                if expandedDiffs.contains(result.id) {
                    ScrollView(.horizontal) {
                        Text(diff)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .frame(maxHeight: 240)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func methodBadge(for requestId: UUID) -> some View {
        if let req = appState.request(byId: requestId) {
            Text(req.method.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(req.method.color, in: RoundedRectangle(cornerRadius: 3))
        } else {
            Text("---")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func statusBadge(_ r: RequestRunResult) -> some View {
        let (text, color): (String, Color) = {
            if let code = r.statusCode {
                let c: Color = (200..<300).contains(code) ? .green : .red
                return ("\(code)", c)
            }
            return ("ERR", .red)
        }()
        return Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: RoundedRectangle(cornerRadius: 3))
    }

    private func durationLabel(_ r: RequestRunResult) -> some View {
        Text("\(r.durationMs) ms")
            .font(.caption.monospacedDigit())
            .foregroundStyle(r.slaViolation ? .orange : .secondary)
    }

    @ViewBuilder
    private func testsBadge(_ r: RequestRunResult) -> some View {
        if r.testResults.isEmpty && r.error == nil && r.snapshotDiff == nil {
            Image(systemName: r.passed ? "checkmark.circle" : "xmark.circle")
                .foregroundStyle(r.passed ? .green : .red)
        } else {
            Image(systemName: r.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(r.passed ? .green : .red)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        let passed = runner.results.filter { $0.passed }.count
        let failed = runner.results.filter { !$0.passed }.count
        let slow = runner.results.filter { $0.slaViolation }.count
        return HStack(spacing: 16) {
            Label("\(passed) passed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Label("\(failed) failed", systemImage: "xmark.circle.fill")
                .foregroundStyle(failed == 0 ? Color.secondary : Color.red)
            Label("\(slow) slow", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(slow == 0 ? Color.secondary : Color.orange)
            Spacer()
            statusLabel
        }
        .font(.caption)
        .padding(12)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch runner.status {
        case .idle:      Text("Idle").foregroundStyle(.secondary)
        case .running:   Text("Running...").foregroundStyle(.blue)
        case .completed: Text("Completed").foregroundStyle(.green)
        case .cancelled: Text("Cancelled").foregroundStyle(.orange)
        }
    }

    // MARK: - Actions

    private func startRun() async {
        expandedDiffs = []
        await runner.run(
            collection: collection,
            settings: appState.runnerSettings,
            environment: appState.selectedEnvironment,
            globals: appState.globalVariables
        )
    }

    private func toggleDiff(_ id: UUID) {
        if expandedDiffs.contains(id) {
            expandedDiffs.remove(id)
        } else {
            expandedDiffs.insert(id)
        }
    }
}
