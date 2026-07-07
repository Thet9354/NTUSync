import SwiftUI

struct ContentView: View {
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
    }
}
