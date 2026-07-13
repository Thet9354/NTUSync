import SwiftUI

struct ContentView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        TabView {
            Tab("Route", systemImage: "bus.fill") {
                RoutePlannerView()
            }
            Tab("Timetable", systemImage: "calendar") {
                TimetableView()
            }
            Tab("Explore", systemImage: "sparkles") {
                BenchesView()
            }
        }
        .task {
            // Rebind to a trip whose Live Activity survived a relaunch.
            if env.tripSession.restoreIfPossible() {
                env.beginTripSensing()
            }
        }
    }
}
