import SwiftUI
import MapKit

struct MapView: UIViewRepresentable {
    let routes: [ScoredRoute]
    let selectedRoute: ScoredRoute?
    @Binding var region: MKCoordinateRegion

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.userTrackingMode = .followWithHeading
        map.mapType = .standard
        map.showsTraffic = true
        map.pointOfInterestFilter = .includingAll
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)
        mapView.region = region

        // Draw non-selected routes dimmed, selected route highlighted
        for route in routes where route.id != selectedRoute?.id {
            let overlay = route.mkRoute.polyline
            overlay.title = "dimmed"
            mapView.addOverlay(overlay, level: .aboveRoads)
        }
        if let selected = selectedRoute {
            let overlay = selected.mkRoute.polyline
            overlay.title = "selected"
            mapView.addOverlay(overlay, level: .aboveRoads)
        }
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        init(_ parent: MapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            if polyline.title == "selected" {
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 6
            } else {
                renderer.strokeColor = UIColor.systemGray.withAlphaComponent(0.5)
                renderer.lineWidth = 3
            }
            return renderer
        }
    }
}
