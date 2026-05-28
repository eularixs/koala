import SwiftUI

/// Lists all schedules for the active project as cards, plus a recent-runs
/// timeline below. PAID feature — the entry point is gated upstream (sidebar
/// + collection context menu), the dashboard itself is reachable only via
/// the sidebar section.
struct AutomationDashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(AutomationSchedulerService.self) private var scheduler

    @State private var showingNewSheet = false
    @State private var editingSchedule: AutomationSchedule? = nil
    @State private var tick = Date()

    /// 1Hz timer drives the "next run in N s" countdown labels without
    /// touching the scheduler internals.
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var schedules: [AutomationSchedule] {
        guard let pid = appState.activeProjectId else { return [] }
        return scheduler.schedules(forProject: pid)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if schedules.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(schedules) { s in
                            scheduleCard(s)
                        }
                        if !recentRuns.isEmpty {
                            Divider().padding(.vertical, 8)
                            Text("Recent Runs")
                                .font(.headline)
                                .padding(.horizontal, 12)
                            ForEach(recentRuns, id: \.id) { r in
                                runRow(r)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .onReceive(countdownTimer) { now in tick = now }
        .sheet(isPresented: $showingNewSheet) {
            ScheduleEditorSheet(editing: nil, preselectedCollectionId: nil)
                .environment(appState)
                .environment(scheduler)
        }
        .sheet(item: $editingSchedule) { s in
            ScheduleEditorSheet(editing: s, preselectedCollectionId: nil)
                .environment(appState)
                .environment(scheduler)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Automation").font(.headline)
                Text("Scheduled collection runs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showingNewSheet = true
            } label: {
                Label("New Schedule", systemImage: "plus")
            }
        }
        .padding(12)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No schedules yet.")
                .foregroundStyle(.secondary)
            Button("Create your first schedule") { showingNewSheet = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Schedule card

    @ViewBuilder
    private func scheduleCard(_ s: AutomationSchedule) -> some View {
        let collectionName = appState.collections.first(where: { $0.id == s.collectionId })?.name ?? "<missing>"
        let envName = s.environmentId.flatMap { id in
            appState.environments.first(where: { $0.id == id })?.name
        }
        let summary = scheduler.lastSummary[s.id]
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(.headline)
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(collectionName)
                            .foregroundStyle(.secondary)
                        if let envName {
                            Text("·").foregroundStyle(.secondary)
                            Image(systemName: "leaf").foregroundStyle(.secondary)
                            Text(envName).foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
                Spacer()
                statusBadge(for: s, summary: summary)
                intervalChip(s.interval)
                enabledToggle(for: s)
            }
            HStack(spacing: 14) {
                lastRunLabel(s, summary: summary)
                nextRunLabel(s)
                Spacer()
                Button {
                    runNow(s)
                } label: {
                    Label("Run Now", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .disabled(scheduler.inFlight.contains(s.id))
                Menu {
                    Button("Edit...") { editingSchedule = s }
                    Divider()
                    Button("Delete", role: .destructive) { deleteSchedule(s) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .font(.caption)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }

    private func statusBadge(for s: AutomationSchedule, summary: AutomationRun?) -> some View {
        let (text, color): (String, Color) = {
            if scheduler.inFlight.contains(s.id) { return ("RUNNING", .blue) }
            guard let summary else { return ("—", .secondary) }
            if summary.failed > 0 { return ("FAIL", .red) }
            return ("PASS", .green)
        }()
        return Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: RoundedRectangle(cornerRadius: 3))
    }

    private func intervalChip(_ interval: AutomationSchedule.Interval) -> some View {
        Text(interval.displayText)
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
    }

    private func enabledToggle(for s: AutomationSchedule) -> some View {
        Toggle("", isOn: Binding(
            get: { s.isEnabled },
            set: { newValue in
                guard let pid = appState.activeProjectId else { return }
                var copy = s
                copy.isEnabled = newValue
                copy.nextRun = newValue ? copy.interval.nextFireDate(from: Date()) : nil
                scheduler.upsert(copy, forProject: pid)
            }
        ))
        .toggleStyle(.switch)
        .labelsHidden()
    }

    @ViewBuilder
    private func lastRunLabel(_ s: AutomationSchedule, summary: AutomationRun?) -> some View {
        if let last = s.lastRun {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                Text("Last: \(Self.shortDate(last))")
                if let summary {
                    Text("·").foregroundStyle(.secondary)
                    Text("\(summary.passed)/\(summary.passed + summary.failed) passed")
                        .foregroundStyle(summary.failed > 0 ? .red : .green)
                }
            }
            .foregroundStyle(.secondary)
        } else {
            Text("Never run").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func nextRunLabel(_ s: AutomationSchedule) -> some View {
        if s.isEnabled, let next = s.nextRun {
            let delta = Int(next.timeIntervalSince(tick))
            HStack(spacing: 4) {
                Image(systemName: "clock")
                if delta <= 0 {
                    Text("Next: due now").foregroundStyle(.blue)
                } else {
                    Text("Next: in \(Self.formatCountdown(delta))").foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Disabled").foregroundStyle(.secondary)
        }
    }

    // MARK: - Recent runs

    private var recentRuns: [(id: UUID, scheduleId: UUID, scheduleName: String, run: AutomationRun)] {
        guard let pid = appState.activeProjectId else { return [] }
        var out: [(id: UUID, scheduleId: UUID, scheduleName: String, run: AutomationRun)] = []
        for s in schedules {
            let runs = scheduler.runs(forSchedule: s.id, projectId: pid)
            for r in runs.prefix(10) {
                out.append((id: r.id, scheduleId: s.id, scheduleName: s.name, run: r))
            }
        }
        out.sort { $0.run.startedAt > $1.run.startedAt }
        return Array(out.prefix(10))
    }

    private func runRow(_ r: (id: UUID, scheduleId: UUID, scheduleName: String, run: AutomationRun)) -> some View {
        HStack(spacing: 10) {
            Image(systemName: r.run.failed > 0 ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(r.run.failed > 0 ? .red : .green)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.scheduleName).font(.body)
                Text(Self.shortDate(r.run.startedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(r.run.passed) passed · \(r.run.failed) failed")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("\(r.run.durationMs) ms")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func runNow(_ s: AutomationSchedule) {
        Task { await scheduler.executeNow(s, appState: appState) }
    }

    private func deleteSchedule(_ s: AutomationSchedule) {
        guard let pid = appState.activeProjectId else { return }
        scheduler.delete(id: s.id, forProject: pid)
    }

    // MARK: - Formatters

    private static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f.string(from: d)
    }

    private static func formatCountdown(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        if m < 60 { return "\(m)m \(s)s" }
        let h = m / 60
        let mm = m % 60
        return "\(h)h \(mm)m"
    }
}
