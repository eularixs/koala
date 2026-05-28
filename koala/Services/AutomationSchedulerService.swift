import Foundation
import Observation
import UserNotifications

/// In-app foreground scheduler for `AutomationSchedule`. Wakes every `tickInterval`
/// seconds, checks each enabled schedule's `nextRun`, and triggers a run via
/// `CollectionRunnerService` when due. The LaunchAgent for out-of-process execution
/// is deferred to a future iteration (license gating prerequisite).
///
/// Wire-up (main agent):
///   - Construct one instance and inject into the SwiftUI environment.
///   - Call `start()` once at app launch (after `AppState.loadFromDisk()`).
@MainActor
@Observable
final class AutomationSchedulerService {

    // MARK: - State

    /// Schedules per project. Loaded lazily on first access per project.
    private var schedulesByProject: [UUID: [AutomationSchedule]] = [:]

    /// Currently-executing schedule IDs (prevents overlap if a previous tick
    /// is still running when the next tick fires).
    private(set) var inFlight: Set<UUID> = []

    /// Most recent run summary per schedule (for live UI without disk I/O).
    private(set) var lastSummary: [UUID: AutomationRun] = [:]

    // MARK: - Dependencies

    private let runStore = AutomationRunStore()
    private let tickInterval: TimeInterval = 30
    private var loopTask: Task<Void, Never>? = nil

    // MARK: - Persistence

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var baseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Koala")
    }

    private func schedulesURL(projectId: UUID) -> URL {
        baseURL
            .appendingPathComponent("projects")
            .appendingPathComponent(projectId.uuidString)
            .appendingPathComponent("automation.json")
    }

    init() {}

    // MARK: - Loop lifecycle

    /// Kicks off the in-app polling loop. Safe to call multiple times (no-op
    /// if already running).
    func start() {
        guard loopTask == nil else { return }
        // Best-effort notification permission request — silent failure if denied.
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: UInt64(30 * 1_000_000_000))
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    // MARK: - Schedule CRUD (per project)

    func schedules(forProject projectId: UUID) -> [AutomationSchedule] {
        if schedulesByProject[projectId] == nil {
            schedulesByProject[projectId] = loadFromDisk(projectId: projectId)
        }
        return schedulesByProject[projectId] ?? []
    }

    func upsert(_ schedule: AutomationSchedule, forProject projectId: UUID) {
        var list = schedules(forProject: projectId)
        var s = schedule
        // Ensure nextRun is populated for a freshly-saved enabled schedule.
        if s.isEnabled && s.nextRun == nil {
            s.nextRun = s.interval.nextFireDate(from: Date())
        }
        if let idx = list.firstIndex(where: { $0.id == s.id }) {
            list[idx] = s
        } else {
            list.append(s)
        }
        schedulesByProject[projectId] = list
        persist(projectId: projectId)
    }

    func delete(id: UUID, forProject projectId: UUID) {
        var list = schedules(forProject: projectId)
        list.removeAll { $0.id == id }
        schedulesByProject[projectId] = list
        runStore.delete(scheduleId: id, forProject: projectId)
        lastSummary.removeValue(forKey: id)
        persist(projectId: projectId)
    }

    func runs(forSchedule scheduleId: UUID, projectId: UUID) -> [AutomationRun] {
        runStore.load(forProject: projectId, scheduleId: scheduleId)
    }

    // MARK: - Execution

    /// Manual "Run Now" trigger from the UI. Bypasses the `nextRun` check.
    func executeNow(_ schedule: AutomationSchedule, appState: AppState) async {
        guard let projectId = appState.activeProjectId else { return }
        await execute(schedule, projectId: projectId, appState: appState)
    }

    /// Wakes up, looks for schedules whose `nextRun <= now && isEnabled`, and
    /// executes them. Iterates all loaded projects.
    private func tick() async {
        let now = Date()
        // Snapshot keys so mutation during iteration is safe.
        let projectIds = Array(schedulesByProject.keys)
        for pid in projectIds {
            let due = (schedulesByProject[pid] ?? []).filter { s in
                guard s.isEnabled, !inFlight.contains(s.id) else { return false }
                guard let next = s.nextRun else { return false }
                return next <= now
            }
            // Execute sequentially per project to avoid hammering the same backend.
            for sched in due {
                // We don't have an AppState reference inside the loop. The
                // executor needs collection + env lookup. Resolution happens
                // via the externally-set `appStateResolver`.
                guard let appState = appStateResolver?() else { continue }
                await execute(sched, projectId: pid, appState: appState)
            }
        }
    }

    /// Set by the host (main agent) so the loop can resolve collections + envs
    /// for due schedules without holding a strong reference itself.
    var appStateResolver: (() -> AppState?)? = nil

    private func execute(_ schedule: AutomationSchedule, projectId: UUID, appState: AppState) async {
        guard !inFlight.contains(schedule.id) else { return }
        inFlight.insert(schedule.id)
        defer { inFlight.remove(schedule.id) }

        // Resolve collection from AppState. Schedules are tied to the active
        // project's collection list.
        guard let collection = appState.collections.first(where: { $0.id == schedule.collectionId }) else {
            // Collection deleted — mark next run anyway so we don't busy-loop.
            advanceNextRun(scheduleId: schedule.id, projectId: projectId)
            return
        }
        let env: KoalaEnvironment? = {
            guard let envId = schedule.environmentId else { return nil }
            return appState.environments.first(where: { $0.id == envId })
        }()

        let runner = CollectionRunnerService()
        let startedAt = Date()
        await runner.run(
            collection: collection,
            settings: appState.runnerSettings,
            environment: env,
            globals: appState.globalVariables
        )
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let results = runner.results
        let passed = results.filter { $0.passed }.count
        let failed = results.filter { !$0.passed }.count
        let slow = results.filter { $0.slaViolation }.count

        let resultsJSON = (try? String(data: encoder.encode(results), encoding: .utf8)) ?? "[]"
        let run = AutomationRun(
            scheduleId: schedule.id,
            startedAt: startedAt,
            durationMs: durationMs,
            passed: passed,
            failed: failed,
            slowCount: slow,
            resultsJSON: resultsJSON
        )
        runStore.append(run, forProject: projectId)
        lastSummary[schedule.id] = run

        // Update schedule lastRun/nextRun
        updateAfterRun(scheduleId: schedule.id, projectId: projectId, ranAt: startedAt)

        // Notifications + webhook
        if schedule.notifyOnFailure && failed > 0 {
            postFailureNotification(schedule: schedule, failed: failed, total: results.count)
        }
        if let webhook = schedule.webhookURL,
           let url = URL(string: webhook),
           !webhook.trimmingCharacters(in: .whitespaces).isEmpty {
            await postWebhook(url: url, schedule: schedule, passed: passed, failed: failed, durationMs: durationMs)
        }
    }

    private func advanceNextRun(scheduleId: UUID, projectId: UUID) {
        guard var list = schedulesByProject[projectId],
              let idx = list.firstIndex(where: { $0.id == scheduleId }) else { return }
        list[idx].nextRun = list[idx].interval.nextFireDate(from: Date())
        schedulesByProject[projectId] = list
        persist(projectId: projectId)
    }

    private func updateAfterRun(scheduleId: UUID, projectId: UUID, ranAt: Date) {
        guard var list = schedulesByProject[projectId],
              let idx = list.firstIndex(where: { $0.id == scheduleId }) else { return }
        list[idx].lastRun = ranAt
        list[idx].nextRun = list[idx].interval.nextFireDate(from: Date())
        schedulesByProject[projectId] = list
        persist(projectId: projectId)
    }

    // MARK: - Notifications + Webhook

    private func postFailureNotification(schedule: AutomationSchedule, failed: Int, total: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Koala: \(schedule.name)"
        content.body = "\(failed) of \(total) request(s) failed."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "koala.automation.\(schedule.id.uuidString).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func postWebhook(
        url: URL,
        schedule: AutomationSchedule,
        passed: Int,
        failed: Int,
        durationMs: Int
    ) async {
        let payload: [String: Any] = [
            "schedule": schedule.name,
            "scheduleId": schedule.id.uuidString,
            "passed": passed,
            "failed": failed,
            "durationMs": durationMs,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Persistence (per project)

    private func loadFromDisk(projectId: UUID) -> [AutomationSchedule] {
        let url = schedulesURL(projectId: projectId)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let list = try? decoder.decode([AutomationSchedule].self, from: data) else {
            return []
        }
        return list
    }

    private func persist(projectId: UUID) {
        let list = schedulesByProject[projectId] ?? []
        let dir = baseURL
            .appendingPathComponent("projects")
            .appendingPathComponent(projectId.uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = schedulesURL(projectId: projectId)
        if let data = try? encoder.encode(list) {
            try? data.write(to: url, options: .atomicWrite)
        }
    }
}
