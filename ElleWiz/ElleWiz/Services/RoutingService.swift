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

    // MARK: - Public API

    func fetchRoutes(
        from origin: MKMapItem,
        to destination: MKMapItem,
        settings: SettingsStore
    ) async {
        isLoading = true
        errorMessage = nil

        let originCoord = origin.placemark.coordinate
        let destCoord   = destination.placemark.coordinate

        do {
            let routes: [ScoredRoute]
            if settings.usingHERE {
                routes = try await fetchHERERoutes(
                    from: originCoord,
                    to: destCoord,
                    settings: settings
                )
            } else {
                routes = try await fetchMapKitRoutes(
                    from: origin,
                    to: destination,
                    settings: settings
                )
            }
            scoredRoutes = routes
            selectedRoute = routes.first
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Live monitoring

    func startMonitoring(destination: MKMapItem, settings: SettingsStore, locationService: LocationService) {
        stopMonitoring()
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard !Task.isCancelled,
                      let self,
                      let location = locationService.currentLocation,
                      let current = await self.selectedRoute else { continue }

                let origin = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))

                var candidates: [ScoredRoute] = []
                if settings.usingHERE {
                    candidates = (try? await fetchHERERoutes(
                        from: location.coordinate,
                        to: destination.placemark.coordinate,
                        settings: settings
                    )) ?? []
                } else {
                    candidates = (try? await fetchMapKitRoutes(
                        from: origin, to: destination, settings: settings
                    )) ?? []
                }

                guard let best = candidates.first else { continue }
                let savedMinutes = current.travelTimeMinutes - best.travelTimeMinutes
                guard savedMinutes >= settings.routeChangeSavingsThresholdMinutes else { continue }

                // Only surface if it's actually a different path
                let differentPath = best.polyline.pointCount != current.polyline.pointCount
                if differentPath {
                    await MainActor.run {
                        self.routeChangeProposal = RouteChangeProposal(
                            currentRoute: current,
                            proposedRoute: best
                        )
                    }
                }
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    func acceptProposedRoute() {
        if let proposal = routeChangeProposal { selectedRoute = proposal.proposedRoute }
        routeChangeProposal = nil
    }

    func dismissProposal() { routeChangeProposal = nil }

    // MARK: - HERE routing

    private func fetchHERERoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        settings: SettingsStore
    ) async throws -> [ScoredRoute] {
        let hereRoutes = try await HERERoutingService.fetchRoutes(
            from: origin,
            to: destination,
            apiKey: settings.hereAPIKey,
            initialChargePercent: settings.evCurrentChargePercent,
            avoidDifficultTurns: settings.avoidLeftTurns
        )

        return hereRoutes.enumerated().map { (i, route) in
            let turns   = HERERoutingService.analyzeTurns(in: route)
            let polyline = HERERoutingService.mkPolyline(for: route)

            // Prefer HERE's reported consumption; fall back to our EVOptimizer estimate.
            let energyKWh: Double
            if route.totalConsumptionWh > 0 {
                energyKWh = route.totalConsumptionWh / 1000.0
            } else {
                energyKWh = EVOptimizer.totalEnergyKWh(
                    distanceMeters: Double(route.totalLengthMeters),
                    durationSeconds: Double(route.totalDurationSeconds),
                    unprotectedLeftTurns: turns.unprotectedLeftCount
                )
            }

            let score = computeScore(
                durationSeconds: Double(route.totalDurationSeconds),
                unprotectedLefts: turns.unprotectedLeftCount,
                energyKWh: energyKWh,
                avoidLeftTurns: settings.avoidLeftTurns
            )

            let label = i == 0 ? "Fastest" : (i == 1 ? "Alternative 1" : "Alternative \(i)")

            return ScoredRoute(
                label: label,
                durationSeconds: Double(route.totalDurationSeconds),
                distanceMeters: Double(route.totalLengthMeters),
                polyline: polyline,
                leftTurnCount: turns.leftCount,
                protectedLeftCount: turns.protectedLeftCount,
                estimatedEnergyKWh: energyKWh,
                score: score,
                mkRoute: nil,
                hereRoute: route
            )
        }.sorted { $0.score < $1.score }
    }

    // MARK: - MapKit routing (fallback)

    private func fetchMapKitRoutes(
        from origin: MKMapItem,
        to destination: MKMapItem,
        settings: SettingsStore
    ) async throws -> [ScoredRoute] {
        let request = MKDirections.Request()
        request.source = origin
        request.destination = destination
        request.transportType = .automobile
        request.requestsAlternateRoutes = true

        let response = try await MKDirections(request: request).calculate()
        return response.routes.map { scoreMapKitRoute($0, settings: settings) }
                              .sorted { $0.score < $1.score }
    }

    private func scoreMapKitRoute(_ route: MKRoute, settings: SettingsStore) -> ScoredRoute {
        let steps = route.steps.map { analyzeMKStep($0) }
        let leftTurns   = steps.filter { $0.direction == .left }.count
        let protected_  = steps.filter { $0.direction == .left && $0.likelyProtected }.count
        let unprotected = leftTurns - protected_

        let energyKWh = EVOptimizer.totalEnergyKWh(
            distanceMeters: route.distance,
            durationSeconds: route.expectedTravelTime,
            unprotectedLeftTurns: unprotected
        )
        let score = computeScore(
            durationSeconds: route.expectedTravelTime,
            unprotectedLefts: unprotected,
            energyKWh: energyKWh,
            avoidLeftTurns: settings.avoidLeftTurns
        )

        let label = route.name.isEmpty ? "Route" : route.name

        return ScoredRoute(
            label: label,
            durationSeconds: route.expectedTravelTime,
            distanceMeters: route.distance,
            polyline: route.polyline,
            leftTurnCount: leftTurns,
            protectedLeftCount: protected_,
            estimatedEnergyKWh: energyKWh,
            score: score,
            mkRoute: route,
            hereRoute: nil
        )
    }

    private func analyzeMKStep(_ step: MKRoute.Step) -> TurnStep {
        let instruction = step.instructions
        let direction = TurnStep.TurnDirection.from(instruction: instruction)
        let lower = instruction.lowercased()
        let likelyProtected = lower.contains("protected") ||
                              lower.contains("green arrow") ||
                              lower.contains("left arrow") ||
                              lower.contains("signal")
        return TurnStep(instruction: instruction, direction: direction, likelyProtected: likelyProtected)
    }

    // MARK: - Shared scoring

    private func computeScore(
        durationSeconds: Double,
        unprotectedLefts: Int,
        energyKWh: Double,
        avoidLeftTurns: Bool
    ) -> Double {
        var score = durationSeconds
        // 75-second virtual penalty per unprotected left (idling + signal cycle)
        if avoidLeftTurns { score += Double(unprotectedLefts) * 75.0 }
        // Small energy term: 60 seconds per kWh as a comfort/range proxy
        score += energyKWh * 60.0
        return score
    }
}
