import CoreLocation
import MapKit

struct HERERoutingService {

    private static let endpoint = "https://router.hereapi.com/v8/routes"

    enum HEREError: Error, LocalizedError {
        case noAPIKey
        case invalidURL
        case httpError(Int, String)
        case decodingError(Error)
        case noRoutes

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "Add your HERE Maps API key in Settings → HERE API Key."
            case .invalidURL:
                return "Could not build routing URL."
            case .httpError(let code, let body):
                return "HERE API error \(code): \(body.prefix(200))"
            case .decodingError(let e):
                return "Failed to parse HERE response: \(e.localizedDescription)"
            case .noRoutes:
                return "HERE returned no routes for this trip."
            }
        }
    }

    // MARK: - Route fetching

    /// Fetches EV-optimised routes from HERE Routing API v8 using the Bolt EUV profile.
    ///
    /// - Parameters:
    ///   - origin: Current device location.
    ///   - destination: Trip destination.
    ///   - apiKey: HERE developer API key (from developer.here.com).
    ///   - initialChargePercent: Battery state-of-charge as a percentage (0–100).
    ///   - avoidDifficultTurns: When true, adds `difficultTurns` and `uTurns` to the avoid list.
    static func fetchRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        apiKey: String,
        initialChargePercent: Double,
        avoidDifficultTurns: Bool
    ) async throws -> [HERERoute] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else { throw HEREError.noAPIKey }

        let initialChargeWh = BoltEUVProfile.usableCapacityWh * (initialChargePercent / 100.0)

        var comps = URLComponents(string: endpoint)!
        var items: [URLQueryItem] = [
            .init(name: "apikey",        value: trimmedKey),
            .init(name: "transportMode", value: "car"),
            .init(name: "origin",        value: "\(origin.latitude),\(origin.longitude)"),
            .init(name: "destination",   value: "\(destination.latitude),\(destination.longitude)"),
            // Request summary (incl. EV consumption), encoded polyline, and turn-by-turn actions
            .init(name: "return",        value: "summary,polyline,actions,instructions"),
            .init(name: "alternatives",  value: "3"),

            // ── Bolt EUV EV parameters ───────────────────────────────────────────────
            // Speed → consumption table (kWh/100m).  See BoltEUVProfile for derivation.
            .init(name: "ev[freeFlowSpeedTable]",  value: BoltEUVProfile.freeFlowTableString()),
            .init(name: "ev[trafficSpeedTable]",   value: BoltEUVProfile.trafficTableString()),
            // Auxiliary load: HVAC + infotainment + 12V bus (kW)
            .init(name: "ev[auxiliaryConsumption]",value: "\(BoltEUVProfile.auxiliaryConsumptionKW)"),
            // Elevation energy model (kWh/m)
            .init(name: "ev[ascent]",              value: "\(BoltEUVProfile.ascentKWhPerMeter)"),
            .init(name: "ev[descent]",             value: "\(BoltEUVProfile.descentKWhPerMeter)"),
            // Battery state
            .init(name: "ev[initialCharge]",       value: "\(Int(initialChargeWh))"),
            .init(name: "ev[maxCharge]",           value: "\(Int(BoltEUVProfile.usableCapacityWh))"),
            // Refuse routes that would strand the car (10% buffer)
            .init(name: "ev[minChargeAtDestination]", value: "\(Int(BoltEUVProfile.minChargeAtDestinationWh))"),
        ]

        if avoidDifficultTurns {
            // "difficultTurns" penalises complex/unprotected turns at the cost matrix level
            items.append(.init(name: "avoid[features]", value: "difficultTurns,uTurns"))
        }

        comps.queryItems = items
        guard let url = comps.url else { throw HEREError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw HEREError.httpError(http.statusCode, body)
        }

        do {
            let decoded = try JSONDecoder().decode(HERERoutesResponse.self, from: data)
            guard !decoded.routes.isEmpty else { throw HEREError.noRoutes }
            return decoded.routes
        } catch let e as HEREError {
            throw e
        } catch {
            throw HEREError.decodingError(error)
        }
    }

    // MARK: - MapKit helpers

    /// Converts the first section's polyline of a HERE route into an MKPolyline for display.
    static func mkPolyline(for route: HERERoute) -> MKPolyline {
        // Concatenate all section polylines into one continuous overlay.
        var allCoords: [CLLocationCoordinate2D] = []
        for section in route.sections where section.type == "vehicle" || section.type == "pedestrian" {
            allCoords += FlexiblePolylineDecoder.decode(section.polyline)
        }
        if allCoords.isEmpty {
            // Fallback: straight line origin→destination
            if let first = route.sections.first,
               let last  = route.sections.last {
                allCoords = [
                    first.departure.place.location.clCoordinate,
                    last.arrival.place.location.clCoordinate
                ]
            }
        }
        return MKPolyline(coordinates: allCoords, count: allCoords.count)
    }

    // MARK: - Turn analysis

    struct TurnAnalysis {
        let leftCount: Int
        let protectedLeftCount: Int
        var unprotectedLeftCount: Int { leftCount - protectedLeftCount }
    }

    /// Counts left turns across all sections. HERE provides direction per action step.
    static func analyzeTurns(in route: HERERoute) -> TurnAnalysis {
        var left = 0
        var protected_ = 0
        for section in route.sections {
            for action in section.actions ?? [] {
                if action.isLeftTurn {
                    left += 1
                    if action.isProtectedLeft { protected_ += 1 }
                }
            }
        }
        return TurnAnalysis(leftCount: left, protectedLeftCount: protected_)
    }
}
