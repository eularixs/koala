import SwiftUI

/// Form sheet for creating or editing an `AutomationSchedule`.
/// TablePlus-style sectioned layout (matches `RunCollectionSheet` chrome).
struct ScheduleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AutomationSchedulerService.self) private var scheduler

    /// Existing schedule to edit. `nil` = create new.
    let editing: AutomationSchedule?

    /// Optional collection to pre-select when invoked from the sidebar
    /// context menu ("Schedule Run...").
    let preselectedCollectionId: UUID?

    // MARK: - Form state

    @State private var name: String = ""
    @State private var collectionId: UUID? = nil
    @State private var environmentId: UUID? = nil
    @State private var intervalKind: IntervalKind = .minutes
    @State private var minutes: Int = 15
    @State private var dailyHour: Int = 9
    @State private var isEnabled: Bool = true
    @State private var notifyOnFailure: Bool = true
    @State private var webhookURL: String = ""

    private enum IntervalKind: String, CaseIterable, Identifiable {
        case minutes = "Minutes"
        case hourly = "Hourly"
        case daily = "Daily"
        var id: String { rawValue }
    }

    init(editing: AutomationSchedule? = nil, preselectedCollectionId: UUID? = nil) {
        self.editing = editing
        self.preselectedCollectionId = preselectedCollectionId
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    basicsSection
                    intervalSection
                    notificationsSection
                }
                .padding(16)
            }
        }
        .frame(minWidth: 520, minHeight: 540)
        .onAppear(perform: hydrate)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(editing == nil ? "New Schedule" : "Edit Schedule").font(.headline)
                Text("Automation").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
        }
        .padding(12)
    }

    // MARK: - Sections

    private var basicsSection: some View {
        SectionCard(title: "Basics") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledField("Name") {
                    TextField("e.g. Smoke test prod", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Collection") {
                    Picker("", selection: $collectionId) {
                        Text("Select...").tag(UUID?.none)
                        ForEach(appState.collections) { col in
                            Text(col.name).tag(Optional(col.id))
                        }
                    }
                    .labelsHidden()
                }
                LabeledField("Environment") {
                    Picker("", selection: $environmentId) {
                        Text("No environment").tag(UUID?.none)
                        ForEach(appState.environments) { env in
                            Text(env.name).tag(Optional(env.id))
                        }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    private var intervalSection: some View {
        SectionCard(title: "Interval") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $intervalKind) {
                    ForEach(IntervalKind.allCases) { k in
                        Text(k.rawValue).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch intervalKind {
                case .minutes:
                    HStack(spacing: 8) {
                        Text("Run every").foregroundStyle(.secondary)
                        Stepper(value: $minutes, in: 1...1440, step: 1) {
                            Text("\(minutes) min").monospacedDigit()
                        }
                        .frame(maxWidth: 220, alignment: .leading)
                    }
                case .hourly:
                    Text("Runs at the top of every hour after first save.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .daily:
                    HStack(spacing: 8) {
                        Text("At hour").foregroundStyle(.secondary)
                        Picker("", selection: $dailyHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(String(format: "%02d:00", h)).tag(h)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 140)
                    }
                }
            }
        }
    }

    private var notificationsSection: some View {
        SectionCard(title: "Notifications") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable on save", isOn: $isEnabled)
                Toggle("Notify on failure (macOS notification)", isOn: $notifyOnFailure)
                LabeledField("Webhook URL (optional)") {
                    TextField("https://hooks.slack.com/...", text: $webhookURL)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Webhook POSTs JSON: {schedule, passed, failed, durationMs} on every run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && collectionId != nil
    }

    private func hydrate() {
        if let e = editing {
            name = e.name
            collectionId = e.collectionId
            environmentId = e.environmentId
            isEnabled = e.isEnabled
            notifyOnFailure = e.notifyOnFailure
            webhookURL = e.webhookURL ?? ""
            switch e.interval {
            case .minutes(let n):
                intervalKind = .minutes; minutes = n
            case .hourly:
                intervalKind = .hourly
            case .daily(let h):
                intervalKind = .daily; dailyHour = h
            }
        } else if let pre = preselectedCollectionId {
            collectionId = pre
        }
    }

    private func save() {
        guard let pid = appState.activeProjectId, let cid = collectionId else { return }
        let interval: AutomationSchedule.Interval = {
            switch intervalKind {
            case .minutes: return .minutes(max(1, minutes))
            case .hourly: return .hourly
            case .daily: return .daily(hour: max(0, min(23, dailyHour)))
            }
        }()
        let trimmedWebhook = webhookURL.trimmingCharacters(in: .whitespaces)
        let schedule = AutomationSchedule(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            collectionId: cid,
            environmentId: environmentId,
            interval: interval,
            isEnabled: isEnabled,
            notifyOnFailure: notifyOnFailure,
            webhookURL: trimmedWebhook.isEmpty ? nil : trimmedWebhook,
            lastRun: editing?.lastRun,
            nextRun: isEnabled ? interval.nextFireDate(from: Date()) : nil,
            createdAt: editing?.createdAt ?? Date()
        )
        scheduler.upsert(schedule, forProject: pid)
        dismiss()
    }
}

// MARK: - Small layout helpers

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .frame(width: 120, alignment: .trailing)
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
