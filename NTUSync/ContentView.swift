import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \Course.code) private var courses: [Course]
    @Query private var settings: [UserSettings]
    @State private var selectedTab: AppTab = .route

    enum AppTab: Hashable {
        case route, timetable, explore
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Route", systemImage: "bus.fill", value: AppTab.route) {
                RoutePlannerView()
            }
            Tab("Timetable", systemImage: "calendar", value: AppTab.timetable) {
                TimetableView()
            }
            Tab("Explore", systemImage: "mappin.and.ellipse", value: AppTab.explore) {
                BenchesView()
            }
        }
        .task {
            // Rebind to a trip whose Live Activity survived a relaunch.
            if env.tripSession.restoreIfPossible() {
                env.beginTripSensing()
            }
            await refreshLeaveAlerts()
        }
        .onChange(of: env.pendingDestination) { _, destination in
            // A tapped leave-now alert lands on the planner, prefilled.
            if destination != nil {
                selectedTab = .route
            }
        }
    }

    /// Roll the leave-alert window forward on every launch; the scheduler
    /// no-ops (and cleans up) when the feature is off.
    private func refreshLeaveAlerts() async {
        guard let userSettings = settings.first else { return }
        await env.leaveAlerts.reschedule(
            sessions: SessionSnapshot.snapshots(of: courses),
            semesterStart: userSettings.semesterStartDate,
            homeNodeID: userSettings.homeNodeID,
            bufferMinutes: userSettings.leaveBufferMinutes,
            enabled: userSettings.leaveAlertsEnabled,
            engine: env.routeEngine
        )
    }
}
