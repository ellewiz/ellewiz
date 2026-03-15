import SwiftUI

@main
struct ElleWizApp: App {
    @StateObject private var locationService = LocationService()
    @StateObject private var routingService = RoutingService()
    @StateObject private var settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationService)
                .environmentObject(routingService)
                .environmentObject(settingsStore)
        }
    }
}
