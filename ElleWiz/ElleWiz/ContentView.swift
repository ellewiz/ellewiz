import SwiftUI
import MapKit

struct ContentView: View {
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var routingService: RoutingService
    @EnvironmentObject var settings: SettingsStore

    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var showSettings = false
    @State private var showRouteSheet = false
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0312),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-screen map
            MapView(
                routes: routingService.scoredRoutes,
                selectedRoute: routingService.selectedRoute,
                region: $mapRegion
            )
            .ignoresSafeArea()
            .onAppear { locationService.requestPermission() }
            .onChange(of: locationService.currentLocation) { _, location in
                if let coord = location?.coordinate, routingService.scoredRoutes.isEmpty {
                    mapRegion.center = coord
                }
            }

            // Top bar: search + settings
            VStack {
                HStack(spacing: 10) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Where to?", text: $searchText)
                            .onSubmit { Task { await performSearch() } }
                        if !searchText.isEmpty {
                            Button { searchText = ""; searchResults = [] } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .padding(10)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Search results dropdown
                if !searchResults.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(searchResults, id: \.self) { item in
                                Button {
                                    selectDestination(item)
                                } label: {
                                    HStack {
                                        Image(systemName: "mappin")
                                            .foregroundStyle(.red)
                                        VStack(alignment: .leading) {
                                            Text(item.name ?? "Unknown")
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                            if let addr = item.placemark.title {
                                                Text(addr)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 10)
                                }
                                Divider().padding(.leading)
                            }
                        }
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .frame(maxHeight: 240)
                    .padding(.horizontal)
                }

                Spacer()
            }

            // Bottom: route cards sheet
            if !routingService.scoredRoutes.isEmpty {
                VStack(spacing: 0) {
                    // Drag handle
                    Capsule()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 36, height: 4)
                        .padding(.top, 8)

                    ScrollView(.vertical) {
                        VStack(spacing: 10) {
                            ForEach(routingService.scoredRoutes) { route in
                                RouteCardView(
                                    route: route,
                                    isSelected: route.id == routingService.selectedRoute?.id,
                                    currentChargePercent: settings.evCurrentChargePercent,
                                    onSelect: { routingService.selectedRoute = route }
                                )
                            }

                            if let selected = routingService.selectedRoute {
                                NavigationButton(route: selected)
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 340)
                }
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(radius: 8)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            // Loading overlay
            if routingService.isLoading {
                ProgressView("Finding best route…")
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Route change proposal overlay
            if let proposal = routingService.routeChangeProposal {
                RouteChangeAlertView(
                    proposal: proposal,
                    onAccept: { routingService.acceptProposedRoute() },
                    onDismiss: { routingService.dismissProposal() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(), value: routingService.routeChangeProposal != nil)
            }
        }
        .alert("Error", isPresented: .constant(routingService.errorMessage != nil)) {
            Button("OK") { routingService.errorMessage = nil }
        } message: {
            Text(routingService.errorMessage ?? "")
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Actions

    private func performSearch() async {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        if let center = locationService.currentLocation?.coordinate {
            request.region = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        }
        let results = try? await MKLocalSearch(request: request).start()
        searchResults = results?.mapItems ?? []
        isSearching = false
    }

    private func selectDestination(_ destination: MKMapItem) {
        searchText = destination.name ?? ""
        searchResults = []

        let origin: MKMapItem
        if let coord = locationService.currentLocation?.coordinate {
            origin = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        } else {
            origin = .forCurrentLocation()
        }

        Task {
            await routingService.fetchRoutes(from: origin, to: destination, settings: settings)
            if let coord = destination.placemark.coordinate as CLLocationCoordinate2D? {
                mapRegion = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: (origin.placemark.coordinate.latitude + coord.latitude) / 2,
                        longitude: (origin.placemark.coordinate.longitude + coord.longitude) / 2
                    ),
                    span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                )
            }
            routingService.startMonitoring(
                destination: destination,
                settings: settings,
                locationService: locationService
            )
        }
    }
}

// MARK: - Open in Apple Maps button

struct NavigationButton: View {
    let route: ScoredRoute

    var body: some View {
        Button {
            // Deep-link into Apple Maps with the polyline's endpoint
            let coordinate = route.polyline.points()[route.polyline.pointCount - 1].coordinate
            let destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            destination.name = route.label
            destination.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        } label: {
            Label("Navigate with Apple Maps", systemImage: "map.fill")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
