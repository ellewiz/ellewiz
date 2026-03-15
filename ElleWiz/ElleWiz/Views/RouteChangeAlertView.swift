import SwiftUI

struct RouteChangeAlertView: View {
    let proposal: RouteChangeProposal
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.blue)
                        .font(.title2)
                    Text("Better Route Found")
                        .font(.headline)
                    Spacer()
                }

                HStack(spacing: 24) {
                    statView(
                        value: String(format: "%.0f min", proposal.timeSavedMinutes),
                        label: "faster",
                        icon: "clock.arrow.circlepath",
                        color: .green
                    )
                    statView(
                        value: String(format: "%.2f kWh", proposal.energySavedKWh),
                        label: "less energy",
                        icon: "bolt.fill",
                        color: .blue
                    )
                    let leftDiff = proposal.currentRoute.leftTurnCount - proposal.proposedRoute.leftTurnCount
                    if leftDiff > 0 {
                        statView(
                            value: "\(leftDiff)",
                            label: "fewer ← turns",
                            icon: "arrow.turn.up.left",
                            color: .orange
                        )
                    }
                }

                HStack(spacing: 12) {
                    Button(action: onDismiss) {
                        Text("Keep Current")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .foregroundStyle(.primary)

                    Button(action: onAccept) {
                        Text("Switch Route")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .foregroundStyle(.white)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 10)
        .padding()
    }

    private func statView(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
