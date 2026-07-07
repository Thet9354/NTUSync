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
            Tab("Benches", systemImage: "chair.lounge.fill") {
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
