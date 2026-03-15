import MapKit
import CoreLocation

// MARK: - Settings

class SettingsStore: ObservableObject {

    // Routing preferences
    @Published var avoidLeftTurns: Bool {
        didSet { UserDefaults.standard.set(avoidLeftTurns, forKey: "avoidLeftTurns") }
    }
    @Published var preferProtectedLeftArrows: Bool {
        didSet { UserDefaults.standard.set(preferProtectedLeftArrows, forKey: "preferProtectedLeft") }
    }
    @Published var routeChangeSavingsThresholdMinutes: Double {
        didSet { UserDefaults.standard.set(routeChangeSavingsThresholdMinutes, forKey: "routeChangeThreshold") }
    }

    // EV / battery (Bolt EUV defaults pre-filled)
    @Published var evCurrentChargePercent: Double {
        didSet { UserDefaults.standard.set(evCurrentChargePercent, forKey: "evCurrentCharge") }
    }

    // HERE Maps API key
    @Published var hereAPIKey: String {
        didSet { UserDefaults.standard.set(hereAPIKey, forKey: "hereAPIKey") }
    }

    var usingHERE: Bool { !hereAPIKey.trimmingCharacters(in: .whitespaces).isEmpty }

    init() {
        let d = UserDefaults.standard
        avoidLeftTurns                  = d.object(forKey: "avoidLeftTurns")      as? Bool   ?? true
        preferProtectedLeftArrows       = d.object(forKey: "preferProtectedLeft") as? Bool   ?? true
        routeChangeSavingsThresholdMinutes = d.object(forKey: "routeChangeThreshold") as? Double ?? 7.0
        evCurrentChargePercent          = d.object(forKey: "evCurrentCharge")     as? Double ?? 80.0
        hereAPIKey                      = d.string(forKey: "hereAPIKey") ?? ""
    }
}

// MARK: - ScoredRoute

/// A route from either MapKit or HERE, enriched with EV and turn-penalty scores.
struct ScoredRoute: Identifiable {
    let id = UUID()

    // Common display data
    let label: String
    let durationSeconds: Double
    let distanceMeters: Double
    let polyline: MKPolyline

    // Scoring
    let leftTurnCount: Int
    let protectedLeftCount: Int
    let estimatedEnergyKWh: Double
    let score: Double                   // lower is better

    // Source (one is non-nil depending on routing provider)
    let mkRoute: MKRoute?
    let hereRoute: HERERoute?

    var travelTimeMinutes: Double { durationSeconds / 60 }
    var distanceMiles: Double     { distanceMeters / 1609.34 }
    var unprotectedLeftCount: Int { leftTurnCount - protectedLeftCount }
}

// MARK: - Turn step (MapKit only — used for MapKit path)

struct TurnStep {
    enum TurnDirection { case left, right, straight, uTurn, unknown }
    let instruction: String
    let direction: TurnDirection
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

// MARK: - Route change proposal

struct RouteChangeProposal: Equatable {
    let currentRoute: ScoredRoute
    let proposedRoute: ScoredRoute

    var timeSavedMinutes: Double { currentRoute.travelTimeMinutes - proposedRoute.travelTimeMinutes }
    var energySavedKWh: Double   { currentRoute.estimatedEnergyKWh - proposedRoute.estimatedEnergyKWh }

    static func == (lhs: RouteChangeProposal, rhs: RouteChangeProposal) -> Bool {
        lhs.currentRoute.id == rhs.currentRoute.id && lhs.proposedRoute.id == rhs.proposedRoute.id
    }
}
