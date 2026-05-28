import SwiftUI

/// Reusable inline editor for a single `RunnerSettings` entry tied to a request.
/// The parent owns the `settings` binding and is responsible for persisting via
/// `AppState.setRunnerSettings(_:for:)`.
struct RunnerSettingsRow: View {
    let requestName: String
    let requestId: UUID

    /// Last response body for the request, used by the "Capture snapshot" button.
    /// nil = no response captured yet (button disabled).
    var lastResponseBody: Data? = nil

    @Binding var settings: RunnerSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: $settings.enabledInRun) {
                    Text(requestName).font(.headline)
                }
                .toggleStyle(.switch)
                Spacer()
            }

            HStack(spacing: 16) {
                // SLA stepper
                HStack(spacing: 6) {
                    Text("SLA")
                    Stepper(
                        value: Binding(
                            get: { settings.slaThresholdMs ?? 0 },
                            set: { settings.slaThresholdMs = $0 == 0 ? nil : $0 }
                        ),
                        in: 0...60_000,
                        step: 100
                    ) {
                        Text(settings.slaThresholdMs.map { "\($0) ms" } ?? "off")
                            .monospacedDigit()
                            .frame(minWidth: 70, alignment: .leading)
                    }
                }

                // Expected status code
                HStack(spacing: 6) {
                    Text("Status")
                    TextField(
                        "any",
                        text: Binding(
                            get: { settings.expectedStatusCode.map(String.init) ?? "" },
                            set: { txt in
                                let trimmed = txt.trimmingCharacters(in: .whitespaces)
                                settings.expectedStatusCode = Int(trimmed)
                            }
                        )
                    )
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    captureSnapshot()
                } label: {
                    Label("Capture snapshot from last response",
                          systemImage: "camera.viewfinder")
                }
                .disabled(lastResponseBody == nil)

                if settings.jsonSnapshot != nil {
                    Button(role: .destructive) {
                        settings.jsonSnapshot = nil
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                }
            }

            if let snap = settings.jsonSnapshot, !snap.isEmpty {
                Text("Snapshot: \(snap.count) bytes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func captureSnapshot() {
        guard let data = lastResponseBody else { return }
        // Try to pretty-format JSON; otherwise store raw UTF-8 string.
        if let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted, .fragmentsAllowed]),
           let s = String(data: pretty, encoding: .utf8) {
            settings.jsonSnapshot = s
        } else {
            settings.jsonSnapshot = String(data: data, encoding: .utf8) ?? ""
        }
    }
}
