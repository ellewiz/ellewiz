import MapKit
import CoreLocation

// MARK: - Settings

class SettingsStore: ObservableObject {
    @Published var avoidLeftTurns: Bool {
        didSet { UserDefaults.standard.set(avoidLeftTurns, forKey: "avoidLeftTurns") }
    }
    @Published var routeChangeSavingsThresholdMinutes: Double {
        didSet { UserDefaults.standard.set(routeChangeSavingsThresholdMinutes, forKey: "routeChangeThreshold") }
    }
    @Published var evBatteryCapacityKWh: Double {
        didSet { UserDefaults.standard.set(evBatteryCapacityKWh, forKey: "evBatteryCapacity") }
    }
    @Published var evCurrentChargePercent: Double {
        didSet { UserDefaults.standard.set(evCurrentChargePercent, forKey: "evCurrentCharge") }
    }
    @Published var evEfficiencyMilesPerKWh: Double {
        didSet { UserDefaults.standard.set(evEfficiencyMilesPerKWh, forKey: "evEfficiency") }
    }
    @Published var preferProtectedLeftArrows: Bool {
        didSet { UserDefaults.standard.set(preferProtectedLeftArrows, forKey: "preferProtectedLeft") }
    }

    init() {
        let defaults = UserDefaults.standard
        self.avoidLeftTurns = defaults.object(forKey: "avoidLeftTurns") as? Bool ?? true
        self.routeChangeSavingsThresholdMinutes = defaults.object(forKey: "routeChangeThreshold") as? Double ?? 7.0
        self.evBatteryCapacityKWh = defaults.object(forKey: "evBatteryCapacity") as? Double ?? 75.0
        self.evCurrentChargePercent = defaults.object(forKey: "evCurrentCharge") as? Double ?? 80.0
        self.evEfficiencyMilesPerKWh = defaults.object(forKey: "evEfficiency") as? Double ?? 3.5
        self.preferProtectedLeftArrows = defaults.object(forKey: "preferProtectedLeft") as? Bool ?? true
    }
}

// MARK: - Route scoring

struct ScoredRoute: Identifiable {
    let id = UUID()
    let mkRoute: MKRoute
    let leftTurnCount: Int
    let protectedLeftCount: Int
    let estimatedEnergyKWh: Double
    let score: Double  // lower is better
    let label: String

    var travelTimeMinutes: Double { mkRoute.expectedTravelTime / 60 }
    var distanceMiles: Double { mkRoute.distance / 1609.34 }
}

// MARK: - Turn analysis

struct TurnStep {
    enum TurnDirection {
        case left, right, straight, uTurn, unknown
    }
    let instruction: String
    let direction: TurnDirection
    /// Heuristic: step name contains "arrow" or uses typical protected-left phrasing
    let likelyProtected: Bool
}

extension TurnStep.TurnDirection {
    static func from(instruction: String) -> TurnStep.TurnDirection {
        let lower = instruction.lowercased()
        if lower.contains("turn left") || lower.contains("left turn") || lower.contains("bear left") { return .left }
        if lower.contains("turn right") || lower.contains("right turn") || lower.contains("bear right") { return .right }
        if lower.contains("u-turn") || lower.contains("uturn") { return .uTurn }
        return .straight
    }
}

// MARK: - Route change alert

struct RouteChangeProposal {
    let currentRoute: ScoredRoute
    let proposedRoute: ScoredRoute
    var timeSavedMinutes: Double { currentRoute.travelTimeMinutes - proposedRoute.travelTimeMinutes }
    var energySavedKWh: Double { currentRoute.estimatedEnergyKWh - proposedRoute.estimatedEnergyKWh }
}
