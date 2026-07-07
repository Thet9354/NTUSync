import Testing
import Foundation
@testable import NTUSync

@MainActor
struct TripSnapshotTests {

    static func makeStore() -> TripSnapshotStore {
        TripSnapshotStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("ntusync-tests-\(UUID().uuidString)"))
    }

    static func makeRoute() -> Route {
        let legs = [
            RouteLeg(kind: .walk, line: nil, nodes: [NodeID("hall.6"), NodeID("stop.hall1")],
                     metres: 200, seconds: 150, boardingTime: nil),
            RouteLeg(kind: .shuttle, line: ShuttleLineID("loop-red"),
                     nodes: [NodeID("stop.hall1"), NodeID("stop.spms")],
                     metres: 900, seconds: 300, boardingTime: .now.addingTimeInterval(240)),
        ]
        return Route(legs: legs, departureTime: .now, arrivalTime: .now.addingTimeInterval(450),
                     totalWalkMetres: 200, exposedMetres: 200)
    }

    @Test func snapshotRoundTripsThroughDisk() {
        let store = Self.makeStore()
        let snapshot = ActiveTripSnapshot(
            activityID: "activity-1", route: Self.makeRoute(), summary: "Hall 6 → SPMS",
            phase: .waitingForBus, stepsSoFar: 420, nextClass: nil
        )
        store.save(snapshot)
        #expect(store.load() == snapshot)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func relaunchRebindsToSurvivingActivity() async throws {
        let store = Self.makeStore()
        let gateway = MockActivityGateway()

        // Session 1: start a trip, advance one phase, then "crash" (drop refs).
        let firstActivity = LiveActivityCoordinator(gateway: gateway)
        let firstSession = TripSessionCoordinator(liveActivity: firstActivity, snapshots: store)
        try await firstSession.start(route: Self.makeRoute(), summary: "Hall 6 → SPMS", nextClass: nil)
        try await firstSession.advance(to: .waitingForBus)

        // Session 2: the activity survived in ActivityKit's registry.
        gateway.preexistingIDs = ["mock-activity-1"]
        let secondActivity = LiveActivityCoordinator(gateway: gateway)
        let secondSession = TripSessionCoordinator(liveActivity: secondActivity, snapshots: store)
        #expect(secondSession.restoreIfPossible())
        #expect(secondSession.phase == .waitingForBus)
        #expect(secondSession.isActive)
        // Restored trips must keep pushing to the same activity.
        try await secondSession.advance(to: .riding)
        #expect(gateway.updateCount >= 2)
    }

    @Test func staleSnapshotIsDiscardedWhenActivityDied() async throws {
        let store = Self.makeStore()
        let gateway = MockActivityGateway()

        let firstActivity = LiveActivityCoordinator(gateway: gateway)
        let firstSession = TripSessionCoordinator(liveActivity: firstActivity, snapshots: store)
        try await firstSession.start(route: Self.makeRoute(), summary: "Hall 6 → SPMS", nextClass: nil)

        // No surviving activities after relaunch (user dismissed it).
        gateway.preexistingIDs = []
        let secondSession = TripSessionCoordinator(
            liveActivity: LiveActivityCoordinator(gateway: gateway), snapshots: store
        )
        #expect(!secondSession.restoreIfPossible())
        #expect(store.load() == nil)   // snapshot cleaned up
    }
}
