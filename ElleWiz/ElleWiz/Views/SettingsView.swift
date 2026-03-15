import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var showAPIKeyTip = false

    var body: some View {
        NavigationStack {
            Form {

                // MARK: HERE API
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: settings.usingHERE ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(settings.usingHERE ? .green : .orange)
                            Text(settings.usingHERE ? "HERE routing active" : "HERE routing inactive — using Apple Maps")
                                .font(.subheadline)
                                .foregroundStyle(settings.usingHERE ? .green : .orange)
                        }

                        SecureField("Paste HERE API key here", text: $settings.hereAPIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("How to get a free key")
                            .font(.caption.bold())
                        Text("""
                            1. Go to developer.here.com and create a free account.
                            2. Create a new project → choose "REST" access.
                            3. Generate an API key and paste it above.
                            Free tier: 250,000 requests/month — plenty for personal use.
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("HERE Maps Routing")
                } footer: {
                    Text("HERE provides EV-aware routing with elevation modelling and the difficultTurns avoidance feature. Without a key the app uses Apple Maps.")
                }

                // MARK: Vehicle
                Section("Vehicle — 2023 Chevrolet Bolt EUV") {
                    labeledRow(label: "Battery (nominal)", value: "65 kWh")
                    labeledRow(label: "Usable capacity (est. at ~24k mi)", value: "63.4 kWh")
                    labeledRow(label: "EPA efficiency", value: "3.54 mi/kWh")
                    labeledRow(label: "Aux draw (HVAC + infotainment)", value: "1.8 kW")
                    labeledRow(label: "Elevation model", value: "On (1,860 kg)")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("About the consumption model")
                            .font(.caption.bold())
                        Text("""
                            The Bolt EUV's speed-to-consumption table is pre-loaded:
                            • City (≤30 km/h):   ~16 kWh/100km
                            • Suburban (50 km/h): ~14 kWh/100km  ← most efficient band
                            • Highway (110 km/h): ~21 kWh/100km
                            Elevation gain/loss is modelled from the vehicle's 1,860 kg \
                            curb weight using HERE's elevation data. Battery degradation \
                            at ~24,000 miles is estimated at 2.5% (63.4 kWh usable).
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // MARK: Battery state
                Section("Current Battery State") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("State of charge")
                            Spacer()
                            Text(String(format: "%.0f%%", settings.evCurrentChargePercent))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.evCurrentChargePercent, in: 5...100, step: 1)
                    }
                    .padding(.vertical, 4)

                    let availableKWh = BoltEUVProfile.usableCapacityWh / 1000
                                     * (settings.evCurrentChargePercent / 100)
                    let estimatedRange = availableKWh * BoltEUVProfile.epaEfficiencyMilesPerKWh
                    labeledRow(
                        label: "Estimated range",
                        value: String(format: "≈ %.0f mi", estimatedRange)
                    )
                }

                // MARK: Left-turn preferences
                Section("Left-Turn Preferences") {
                    Toggle("Penalise unprotected left turns", isOn: $settings.avoidLeftTurns)
                    Toggle("Prefer routes with protected green-arrow lefts", isOn: $settings.preferProtectedLeftArrows)

                    if settings.avoidLeftTurns {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("How scoring works")
                                .font(.caption.bold())
                            Text("""
                                Each unprotected left turn adds a 75-second virtual penalty to \
                                a route's score (45 s idle + ~30 s signal cycle). Routes with \
                                fewer unprotected lefts rank higher when travel times are similar.
                                When HERE routing is active, the API also applies its own \
                                difficultTurns avoidance at the routing cost-matrix level.
                                """)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // MARK: Route-change sensitivity
                Section("Route-Change Sensitivity") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Minimum savings to suggest a switch")
                            Spacer()
                            Text(String(format: "%.0f min", settings.routeChangeSavingsThresholdMinutes))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.routeChangeSavingsThresholdMinutes, in: 2...20, step: 1)
                    }
                    .padding(.vertical, 4)
                }

                // MARK: Limitations note
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Neither Apple Maps nor HERE exposes real-time traffic-signal phase data, so the app cannot definitively know which intersections have a protected left-turn arrow. \"Protected\" turns are inferred from the phrasing of navigation instructions. Accuracy depends on how each provider phrases directions in your area.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Signal data limitation")
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

    @ViewBuilder
    private func labeledRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
