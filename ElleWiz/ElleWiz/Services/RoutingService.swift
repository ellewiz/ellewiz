import MapKit
import Combine

@MainActor
class RoutingService: ObservableObject {
    @Published var scoredRoutes: [ScoredRoute] = []
    @Published var selectedRoute: ScoredRoute?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var routeChangeProposal: RouteChangeProposal?

    private var monitoringTask: Task<Void, Never>?
    private var currentDestination: MKMapItem?

    // MARK: - Route fetching

    func fetchRoutes(
        from origin: MKMapItem,
        to destination: MKMapItem,
        settings: SettingsStore
    ) async {
        isLoading = true
        errorMessage = nil
        currentDestination = destination

        let request = MKDirections.Request()
        request.source = origin
        request.destination = destination
        request.transportType = .automobile
        request.requestsAlternateRoutes = true

        do {
            let directions = MKDirections(request: request)
            let response = try await directions.calculate()

            let scored = response.routes.map { route in
                score(route: route, settings: settings)
            }.sorted { $0.score < $1.score }

            scoredRoutes = scored
            selectedRoute = scored.first
        } catch {
            errorMessage = "Could not find routes: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Live route monitoring

    func startMonitoring(destination: MKMapItem, settings: SettingsStore, locationService: LocationService) {
        currentDestination = destination
        stopMonitoring()
        monitoringTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000) // check every 60s
                guard !Task.isCancelled,
                      let location = locationService.currentLocation,
                      let current = selectedRoute else { continue }

                let origin = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
                let request = MKDirections.Request()
                request.source = origin
                request.destination = destination
                request.transportType = .automobile
                request.requestsAlternateRoutes = true

                guard let response = try? await MKDirections(request: request).calculate() else { continue }

                let candidates = response.routes.map { score(route: $0, settings: settings) }
                guard let best = candidates.sorted(by: { $0.score < $1.score }).first else { continue }

                let savedMinutes = current.travelTimeMinutes - best.travelTimeMinutes
                if savedMinutes >= settings.routeChangeSavingsThresholdMinutes
                    && best.mkRoute.polyline.pointCount != current.mkRoute.polyline.pointCount {
                    routeChangeProposal = RouteChangeProposal(currentRoute: current, proposedRoute: best)
                }
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    func acceptProposedRoute() {
        if let proposal = routeChangeProposal {
            selectedRoute = proposal.proposedRoute
        }
        routeChangeProposal = nil
    }

    func dismissProposal() {
        routeChangeProposal = nil
    }

    // MARK: - Scoring

    private func score(route: MKRoute, settings: SettingsStore) -> ScoredRoute {
        let steps = route.steps.map { analyzeTurn(step: $0) }

        let leftTurns = steps.filter { $0.direction == .left }.count
        let protectedLefts = steps.filter { $0.direction == .left && $0.likelyProtected }.count
        let unprotectedLefts = leftTurns - protectedLefts

        let energyKWh = EVOptimizer.totalEnergyKWh(for: route, unprotectedLeftTurns: unprotectedLefts)

        // Score = time (s) + penalty per unprotected left (45s idle + signal cycle wait ~30s)
        //       + small EV penalty for energy cost
        var rawScore = route.expectedTravelTime
        if settings.avoidLeftTurns {
            rawScore += Double(unprotectedLefts) * 75.0 // 75s virtual penalty each
        }
        rawScore += energyKWh * 60.0 // 60s per kWh as a comfort/range factor

        let label: String
        switch route.name.isEmpty ? "Route \(route.transportType.rawValue)" : route.name {
        case let n where !n.isEmpty: label = n
        default: label = "Route"
        }

        return ScoredRoute(
            mkRoute: route,
            leftTurnCount: leftTurns,
            protectedLeftCount: protectedLefts,
            estimatedEnergyKWh: energyKWh,
            score: rawScore,
            label: label
        )
    }

    private func analyzeTurn(step: MKRoute.Step) -> TurnStep {
        let instruction = step.instructions
        let direction = TurnStep.TurnDirection.from(instruction: instruction)

        // Heuristic: "protected", "green arrow", or "signal" language in the step notice
        let lower = instruction.lowercased()
        let likelyProtected = lower.contains("protected") ||
                              lower.contains("green arrow") ||
                              lower.contains("left arrow") ||
                              lower.contains("signal")

        return TurnStep(instruction: instruction, direction: direction, likelyProtected: likelyProtected)
    }
}
