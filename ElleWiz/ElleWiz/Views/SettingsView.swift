import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Left Turn Preferences") {
                    Toggle("Avoid Unprotected Left Turns", isOn: $settings.avoidLeftTurns)
                    Toggle("Prefer Routes With Protected Left Arrows", isOn: $settings.preferProtectedLeftArrows)

                    if settings.avoidLeftTurns {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("How It Works")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Routes are scored to penalize unprotected left turns (no green arrow). When two routes have similar travel times, the one with fewer unprotected lefts is preferred.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Route Change Sensitivity") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Minimum time savings to suggest a new route")
                            Spacer()
                            Text(String(format: "%.0f min", settings.routeChangeSavingsThresholdMinutes))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: $settings.routeChangeSavingsThresholdMinutes,
                            in: 2...20,
                            step: 1
                        )
                    }
                    .padding(.vertical, 4)
                }

                Section("EV Settings") {
                    HStack {
                        Text("Battery Capacity")
                        Spacer()
                        TextField("kWh", value: $settings.evBatteryCapacityKWh, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kWh")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Current Charge")
                            Spacer()
                            Text(String(format: "%.0f%%", settings.evCurrentChargePercent))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: $settings.evCurrentChargePercent,
                            in: 0...100,
                            step: 1
                        )
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("Efficiency")
                        Spacer()
                        TextField("mi/kWh", value: $settings.evEfficiencyMilesPerKWh, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("mi/kWh")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Efficiency Guidance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Most EVs average 3–4 mi/kWh in mixed driving. Check your car's trip computer for your real-world number.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("About Left-Turn Detection") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Note on Accuracy")
                            .font(.caption.bold())
                        Text("""
                            Apple Maps does not expose real-time traffic signal data. \
                            Left-turn detection is based on step-by-step navigation instructions. \
                            "Protected" turns are inferred from phrasing in the directions text. \
                            Accuracy varies by map data quality in your area.
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
