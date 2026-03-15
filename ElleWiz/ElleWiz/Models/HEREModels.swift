import CoreLocation

// MARK: - HERE Routing API v8 Response Models

struct HERERoutesResponse: Decodable {
    let routes: [HERERoute]
}

struct HERERoute: Decodable {
    let id: String
    let sections: [HERESection]

    var totalDurationSeconds: Int { sections.reduce(0) { $0 + $1.summary.duration } }
    var totalLengthMeters: Int    { sections.reduce(0) { $0 + $1.summary.length } }
    /// Energy consumed across all vehicle sections (Wh), from summary if available.
    var totalConsumptionWh: Double {
        sections.compactMap { $0.summary.consumption }.reduce(0, +)
    }
}

struct HERESection: Decodable {
    let id: String
    let type: String
    let departure: HEREDeparture
    let arrival: HEREArrival
    let summary: HERESummary
    let polyline: String
    let actions: [HEREAction]?
}

struct HEREDeparture: Decodable {
    let time: String
    let place: HERENamedLocation
}

struct HEREArrival: Decodable {
    let time: String
    let place: HERENamedLocation
}

struct HERENamedLocation: Decodable {
    let location: HERECoordinate
}

struct HERECoordinate: Decodable {
    let lat: Double
    let lng: Double

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

struct HERESummary: Decodable {
    let duration: Int       // seconds (with traffic)
    let length: Int         // meters
    let baseDuration: Int?  // seconds without traffic
    let consumption: Double? // Wh consumed — returned when EV params are provided
}

struct HEREAction: Decodable {
    let action: String
    let duration: Int?
    let length: Int?
    let instruction: String?
    /// HERE direction values: "left", "right", "forward", "bearLeft", "bearRight",
    /// "slightLeft", "slightRight", "sharpLeft", "sharpRight", "uTurn"
    let direction: String?

    var isLeftTurn: Bool {
        guard let d = direction else { return false }
        return d == "left" || d == "sharpLeft"
    }

    var isProtectedLeft: Bool {
        guard isLeftTurn else { return false }
        let text = (instruction ?? "").lowercased()
        return text.contains("protected") || text.contains("green arrow") || text.contains("left arrow")
    }
}

// MARK: - 2023 Chevrolet Bolt EUV Vehicle Profile

/// Physical constants and consumption data for the 2023 Bolt EUV (~24,000 miles).
enum BoltEUVProfile {
    /// Nominal battery capacity in Wh.
    static let nominalCapacityWh: Double = 65_000

    /// Estimated usable capacity at ~24k miles (≈2.5% degradation vs. new).
    /// Bolt EUs degrade minimally; NHTSA and owner data suggest 2–4% by 25k mi.
    static let usableCapacityWh: Double = 63_375

    /// 10% safety reserve at destination in Wh.
    static let minChargeAtDestinationWh: Double = 6_500

    /// Auxiliary power draw in kW (HVAC, infotainment, headlights, 12V bus).
    static let auxiliaryConsumptionKW: Double = 1.8

    /// Energy consumed per meter of elevation gain (kWh/m).
    /// Derived from: mass(1,860 kg) × g(9.81 m/s²) / (motor efficiency 0.85 × 3,600,000 J/kWh)
    static let ascentKWhPerMeter: Double = 0.00597

    /// Energy recovered per meter of elevation loss via regenerative braking (kWh/m).
    /// Regen round-trip efficiency ≈ 55% for the Bolt.
    static let descentKWhPerMeter: Double = 0.00328

    /// Speed-consumption lookup table for HERE API.
    /// Units: speed in km/h, consumption in kWh/100m (= kWh/100km ÷ 1000).
    ///
    /// Real-world Bolt EUV data:
    ///   City  ~14–16 kWh/100km → 0.014–0.016 kWh/100m
    ///   Hwy   ~18–22 kWh/100km → 0.018–0.022 kWh/100m
    ///   EPA combined: 28 kWh/100mi ≈ 17.4 kWh/100km = 0.0174 kWh/100m
    static let freeFlowSpeedTable: [(speedKph: Int, kwhPer100m: Double)] = [
        (0,   0.020),   // standstill — aux-dominated loss per notional meter
        (10,  0.025),   // heavy stop-and-go
        (30,  0.016),   // urban (regen helps significantly)
        (50,  0.014),   // suburban sweet spot
        (70,  0.0152),  // light freeway
        (90,  0.0175),  // freeway
        (110, 0.021),   // US highway (~68 mph)
        (130, 0.0275),  // 81 mph
        (250, 0.060),   // extrapolated upper bound
    ]

    /// Traffic-speed table — identical to free-flow for this profile.
    static let trafficSpeedTable = freeFlowSpeedTable

    static func freeFlowTableString() -> String {
        freeFlowSpeedTable.map { "\($0.speedKph),\($0.kwhPer100m)" }.joined(separator: ",")
    }

    static func trafficTableString() -> String { freeFlowTableString() }

    /// EPA-rated efficiency used for range estimates when HERE doesn't return consumption.
    static let epaEfficiencyMilesPerKWh: Double = 3.54  // 100mi / 28.2 kWh
}
