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

        pedometer.onUpdate = { [tripSession] steps, distanceDelta in
            tripSession.recordSteps(steps)
            tripSession.recordDistanceDelta(distanceDelta)
        }
        tripSession.nodeLocator = { [graph] node in
            graph.nodes[node]?.coordinate
        }
        location.onFix = { [tripSession] fix, accuracy in
            tripSession.ingest(fix: fix, accuracy: accuracy)
        }
        location.onGPSDenialChange = { [tripSession] denied in
            tripSession.setGPSDenied(denied)
        }
        tripSession.onReplanNeeded = { [weak self] fix in
            self?.replanActiveTrip(from: fix)
        }
    }

    func displayName(for node: NodeID) -> String {
        graph.nodes[node]?.displayName ?? node.rawValue
    }

    /// Begin per-trip sensing; called when a trip starts.
    func beginTripSensing() {
        location.requestPermission()
        location.setTier(.cruise)
        location.startUpdates()
        pedometer.start()
    }

    /// Tear down per-trip sensing; called when a trip ends.
    func endTripSensing() {
        pedometer.stop()
        location.setTier(.idle)
        location.stopUpdates()
    }

    /// Re-route the active trip from a fresh fix (§5.1 re-acquisition rule).
    private func replanActiveTrip(from fix: GeoPoint) {
        guard let destination = tripSession.route?.destination else { return }
        let profile = tripSession.profile ?? .fastest
        Task {
            guard let origin = await routeEngine.nearestNode(to: fix, where: { !$0.isIndoor }) else { return }
            do {
                let newRoute = try await routeEngine.route(
                    RouteQuery(origin: origin, destination: destination, departure: .now, profile: profile)
                )
                await tripSession.updateRoute(newRoute)
            } catch {
                Logger.routing.error("mid-trip replan failed: \(String(describing: error))")
            }
        }
    }
}
