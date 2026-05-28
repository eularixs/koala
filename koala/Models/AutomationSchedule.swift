import Foundation

/// A user-configured recurring run for a collection. Lives per-project on disk
/// at `Application Support/Koala/projects/{pid}/automation.json`.
///
/// NOTE: In-app foreground execution only in this iteration. A LaunchAgent for
/// out-of-process background runs is deferred until license gating ships.
struct AutomationSchedule: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var collectionId: UUID
    var environmentId: UUID?
    var interval: Interval
    var isEnabled: Bool
    var notifyOnFailure: Bool
    var webhookURL: String?
    var lastRun: Date?
    var nextRun: Date?
    var createdAt: Date

    enum Interval: Codable, Hashable {
        case minutes(Int)
        case hourly
        case daily(hour: Int)        // 0-23
        // .custom cron deferred

        /// Human-friendly description, e.g. "every 15 min", "hourly", "daily at 09:00".
        var displayText: String {
            switch self {
            case .minutes(let n):
                if n == 1 { return "every minute" }
                return "every \(n) min"
            case .hourly:
                return "hourly"
            case .daily(let h):
                return String(format: "daily at %02d:00", max(0, min(23, h)))
            }
        }

        /// Computes the next firing date strictly after `from`.
        func nextFireDate(from: Date, calendar: Calendar = .current) -> Date {
            switch self {
            case .minutes(let n):
                let mins = max(1, n)
                return from.addingTimeInterval(TimeInterval(mins * 60))
            case .hourly:
                return from.addingTimeInterval(3600)
            case .daily(let hour):
                let h = max(0, min(23, hour))
                var comps = calendar.dateComponents([.year, .month, .day], from: from)
                comps.hour = h
                comps.minute = 0
                comps.second = 0
                let today = calendar.date(from: comps) ?? from
                if today > from { return today }
                return calendar.date(byAdding: .day, value: 1, to: today) ?? from.addingTimeInterval(86400)
            }
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        collectionId: UUID,
        environmentId: UUID? = nil,
        interval: Interval,
        isEnabled: Bool = true,
        notifyOnFailure: Bool = true,
        webhookURL: String? = nil,
        lastRun: Date? = nil,
        nextRun: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.collectionId = collectionId
        self.environmentId = environmentId
        self.interval = interval
        self.isEnabled = isEnabled
        self.notifyOnFailure = notifyOnFailure
        self.webhookURL = webhookURL
        self.lastRun = lastRun
        self.nextRun = nextRun
        self.createdAt = createdAt
    }
}

/// History entry for one execution of a schedule. Persisted under
/// `Application Support/Koala/projects/{pid}/automation/runs-{scheduleId}.json`,
/// capped at 200 newest entries via `AutomationRunStore`.
struct AutomationRun: Identifiable, Codable, Hashable {
    var id: UUID
    var scheduleId: UUID
    var startedAt: Date
    var durationMs: Int
    var passed: Int
    var failed: Int
    var slowCount: Int
    var resultsJSON: String

    init(
        id: UUID = UUID(),
        scheduleId: UUID,
        startedAt: Date,
        durationMs: Int,
        passed: Int,
        failed: Int,
        slowCount: Int,
        resultsJSON: String
    ) {
        self.id = id
        self.scheduleId = scheduleId
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.passed = passed
        self.failed = failed
        self.slowCount = slowCount
        self.resultsJSON = resultsJSON
    }
}
