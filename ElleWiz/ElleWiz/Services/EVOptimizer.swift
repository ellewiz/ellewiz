import MapKit

/// Estimates energy consumption for display and range checks.
/// When a HERE API key is set, HERE's own EV engine provides the primary consumption figure;
/// this struct is then used only for the fallback (MapKit routes) and UI display.
struct EVOptimizer {

    // MARK: - 2023 Bolt EUV consumption model

    // kWh/mile at different average speed bands (from EPA and real-world Bolt EUV data).
    private static let urbanKWhPerMile    = 0.248  // <30 mph — regen helps in city
    private static let suburbanKWhPerMile = 0.222  // 30–55 mph — sweet spot
    private static let highwayKWhPerMile  = 0.286  // >55 mph — aero drag dominates

    /// Idle penalty per unprotected left turn: ~45 s at ~0.5 kW draw (HVAC + electronics).
    static let idlePenaltyKWhPerUnprotectedLeft: Double = 0.5 * (45.0 / 3600.0)  // ≈0.00625 kWh

    // MARK: - Public API

    /// Estimates total energy in kWh for a route defined by distance and duration.
    static func totalEnergyKWh(
        distanceMeters: Double,
        durationSeconds: Double,
        unprotectedLeftTurns: Int
    ) -> Double {
        let distanceMiles = distanceMeters / 1609.34
        let avgSpeedMPS   = distanceMeters / max(durationSeconds, 1)
        let avgSpeedMPH   = avgSpeedMPS * 2.23694

        let kwhPerMile: Double
        switch avgSpeedMPH {
        case ..<30:  kwhPerMile = urbanKWhPerMile
        case 30..<55: kwhPerMile = suburbanKWhPerMile
        default:     kwhPerMile = highwayKWhPerMile
        }

        let base    = distanceMiles * kwhPerMile
        let penalty = Double(unprotectedLeftTurns) * idlePenaltyKWhPerUnprotectedLeft
        return base + penalty
    }

    /// Remaining range in miles after completing a route, given current battery state.
    static func remainingRangeMiles(
        currentChargePercent: Double,
        routeEnergyKWh: Double
    ) -> Double {
        let availableKWh  = BoltEUVProfile.usableCapacityWh / 1000.0 * (currentChargePercent / 100.0)
        let remainingKWh  = availableKWh - routeEnergyKWh
        return max(0, remainingKWh * BoltEUVProfile.epaEfficiencyMilesPerKWh)
    }

    /// Returns true if the battery has enough charge to complete the route with a 10% buffer.
    static func isSufficientCharge(
        currentChargePercent: Double,
        routeEnergyKWh: Double
    ) -> Bool {
        let reservePercent = 10.0
        let availableKWh   = BoltEUVProfile.usableCapacityWh / 1000.0
                           * ((currentChargePercent - reservePercent) / 100.0)
        return availableKWh >= routeEnergyKWh
    }
}
