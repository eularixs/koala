import SwiftUI

// MARK: - DeploymentStatusView

/// Reusable status indicator: colored dot + text label + spinner for .deploying.
struct DeploymentStatusView: View {
    let status: MockServerStatus
    let lastDeployedAt: Date?

    var body: some View {
        HStack(spacing: 6) {
            statusIndicator
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(statusColor)
            if let date = lastDeployedAt, status == .live {
                Text("· \(date.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if status == .deploying {
            ProgressView()
                .scaleEffect(0.55)
                .frame(width: 10, height: 10)
        } else {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
    }

    private var statusColor: Color {
        switch status {
        case .live:        return .green
        case .deploying:   return .yellow
        case .error:       return .red
        case .notDeployed: return .secondary
        }
    }

    private var statusLabel: String {
        status.displayName
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        DeploymentStatusView(status: .live, lastDeployedAt: Date().addingTimeInterval(-3600))
        DeploymentStatusView(status: .deploying, lastDeployedAt: nil)
        DeploymentStatusView(status: .error, lastDeployedAt: nil)
        DeploymentStatusView(status: .notDeployed, lastDeployedAt: nil)
    }
    .padding()
}
