import Foundation
import os

/// Composition root: immutable topology + long-lived services.
@MainActor
@Observable
final class AppEnvironment {
    let graph: CampusGraph
    let timetable: ShuttleTimetable
    let routeEngine: RouteEngine
    let liveActivity: LiveActivityCoordinator
    let tripSession: TripSessionCoordinator
    let location: LocationService
    let pedometer: PedometerService

    init() {
        do {
            graph = try CampusGraph.loadBundled()
            timetable = try ShuttleTimetable.loadBundled()
        } catch {
            // Bundled data is a build artifact; failing to parse it is a
            // programmer error caught by the validation test suite.
            Logger.routing.fault("bundled data unloadable: \(String(describing: error))")
            fatalError("NTUSync bundled campus data is corrupt: \(error)")
        }
        routeEngine = RouteEngine(graph: graph, timetable: timetable)
        liveActivity = LiveActivityCoordinator()
        tripSession = TripSessionCoordinator(liveActivity: liveActivity)
        location = LocationService()
        pedometer = PedometerService()

        pedometer.onUpdate = { [tripSession] steps, _ in
            tripSession.recordSteps(steps)
        }
    }

    func displayName(for node: NodeID) -> String {
        graph.nodes[node]?.displayName ?? node.rawValue
    }
}
