import MapKit

/// Estimates energy consumption for a route and scores it for EV efficiency.
struct EVOptimizer {

    // Approximate kWh/mile at different speed bands (highway, suburban, urban)
    private static let highwayConsumption = 0.30   // kWh/mile >55 mph
    private static let suburbanConsumption = 0.25  // kWh/mile 30-55 mph
    private static let urbanConsumption = 0.20     // kWh/mile <30 mph (more regen)

    /// Returns estimated kWh needed to complete the route.
    static func estimatedEnergyKWh(for route: MKRoute) -> Double {
        let distanceMiles = route.distance / 1609.34
        let avgSpeedMPS = route.distance / max(route.expectedTravelTime, 1)
        let avgSpeedMPH = avgSpeedMPS * 2.23694

        let kwhPerMile: Double
        switch avgSpeedMPH {
        case ..<30:
            kwhPerMile = urbanConsumption
        case 30..<55:
            kwhPerMile = suburbanConsumption
        default:
            kwhPerMile = highwayConsumption
        }

        // Stop-and-go penalty: each left turn that isn't protected costs extra idle time
        // (this is refined by the turn count supplied externally)
        return distanceMiles * kwhPerMile
    }

    /// Applies a penalty (in kWh) per unprotected left turn due to idling.
    /// Average idle at a light ~45 seconds; EV draws ~0.5 kW while stopped (HVAC, electronics).
    static let idlePenaltyPerUnprotectedLeftKWh: Double = 0.5 * (45.0 / 3600.0)

    /// Computes total estimated energy including turn penalties.
    static func totalEnergyKWh(for route: MKRoute, unprotectedLeftTurns: Int) -> Double {
        let base = estimatedEnergyKWh(for: route)
        let penalty = Double(unprotectedLeftTurns) * idlePenaltyPerUnprotectedLeftKWh
        return base + penalty
    }

    /// Returns remaining range in miles after completing the route.
    static func remainingRangeMiles(
        batteryCapacityKWh: Double,
        currentChargePercent: Double,
        efficiencyMilesPerKWh: Double,
        routeEnergyKWh: Double
    ) -> Double {
        let availableKWh = batteryCapacityKWh * (currentChargePercent / 100.0)
        let remainingKWh = availableKWh - routeEnergyKWh
        return max(0, remainingKWh * efficiencyMilesPerKWh)
    }

    /// True if battery charge is sufficient to complete the route with a 10% buffer.
    static func isSufficientCharge(
        batteryCapacityKWh: Double,
        currentChargePercent: Double,
        routeEnergyKWh: Double
    ) -> Bool {
        let availableKWh = batteryCapacityKWh * ((currentChargePercent - 10.0) / 100.0)
        return availableKWh >= routeEnergyKWh
    }
}
