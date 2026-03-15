import SwiftUI

struct RouteCardView: View {
    let route: ScoredRoute
    let isSelected: Bool
    let currentChargePercent: Double
    let onSelect: () -> Void

    private var remainingRange: Double {
        EVOptimizer.remainingRangeMiles(
            currentChargePercent: currentChargePercent,
            routeEnergyKWh: route.estimatedEnergyKWh
        )
    }

    private var hasSufficientCharge: Bool {
        EVOptimizer.isSufficientCharge(
            currentChargePercent: currentChargePercent,
            routeEnergyKWh: route.estimatedEnergyKWh
        )
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(route.label)
                        .font(.headline)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }

                HStack(spacing: 16) {
                    Label(formatTime(route.travelTimeMinutes), systemImage: "clock")
                    Label(String(format: "%.1f mi", route.distanceMiles), systemImage: "arrow.triangle.swap")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Label(String(format: "%.2f kWh", route.estimatedEnergyKWh), systemImage: "bolt.fill")
                        .foregroundStyle(hasSufficientCharge ? .green : .red)
                    Label(String(format: "%.0f mi left", remainingRange), systemImage: "battery.75")
                        .foregroundStyle(remainingRange > 20 ? .primary : .orange)
                }
                .font(.subheadline)

                HStack(spacing: 8) {
                    turnBadge(count: route.unprotectedLeftCount, label: "unprotected ←", color: .orange)
                    turnBadge(count: route.protectedLeftCount,   label: "protected ←",   color: .green)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func turnBadge(count: Int, label: String, color: Color) -> some View {
        if count > 0 {
            Text("\(count) \(label)")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(Capsule())
        }
    }

    private func formatTime(_ minutes: Double) -> String {
        let m = Int(minutes)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m) min"
    }
}
