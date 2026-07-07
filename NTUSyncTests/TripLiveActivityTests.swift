import Testing
import Foundation
@testable import NTUSync

@MainActor
final class MockActivityGateway: TripActivityGateway {
    var enabled = true
    var preexistingIDs: [String] = []
    var startCount = 0
    var updateCount = 0
    var endedIDs: [String] = []

    var areActivitiesEnabled: Bool { enabled }

    func existingActivityIDs() -> [String] { preexistingIDs }

    func start(attributes: TripActivityAttributes,
               state: TripActivityAttributes.ContentState,
               staleDate: Date) throws -> String {
        startCount += 1
        return "mock-activity-\(startCount)"
    }

    func update(id: String, state: TripActivityAttributes.ContentState,
                staleDate: Date, relevanceScore: Double) async {
        updateCount += 1
    }

    func end(id: String, state: TripActivityAttributes.ContentState?,
             dismissal: ActivityDismissal) async {
        endedIDs.append(id)
        preexistingIDs.removeAll { $0 == id }
    }
}

@MainActor
struct TripStateMachineTests {

    @Test func fullBusTripIsLegal() throws {
        var machine = TripStateMachine(initial: .walkingToStop)
        try machine.advance(to: .waitingForBus)
        try machine.advance(to: .riding)
        try machine.advance(to: .walkingToClass)
        try machine.advance(to: .arrived)
        #expect(machine.phase == .arrived)
    }

    @Test func missedBusBailOutIsLegal() throws {
        var machine = TripStateMachine(initial: .walkingToStop)
        try machine.advance(to: .waitingForBus)
        try machine.advance(to: .walkingToClass)   // gave up and walked
        #expect(machine.phase == .walkingToClass)
    }

    @Test func illegalTransitionsThrow() {
        var machine = TripStateMachine(initial: .walkingToStop)
        #expect(throws: TripStateError.illegalTransition(from: .walkingToStop, to: .riding)) {
            try machine.advance(to: .riding)
        }
        var arrived = TripStateMachine(initial: .arrived)
        #expect(throws: TripStateError.self) {
            try arrived.advance(to: .walkingToClass)
        }
    }
}

@MainActor
struct LiveActivityCoordinatorTests {

    static func sampleState(phase: TripPhase, steps: Int = 0) -> TripActivityAttributes.ContentState {
        TripActivityAttributes.ContentState(
            phase: phase,
            busLineName: "loop-red",
            boardingWindow: nil,
            arrivalEstimate: Date(timeIntervalSinceReferenceDate: 800_000_000),
            nextClass: nil,
            stepsSoFar: steps
        )
    }

    static func sampleAttributes() -> TripActivityAttributes {
        TripActivityAttributes(routeSummary: "Hall 6 → SPMS", destinationNodeID: "bldg.spms")
    }

    @Test func disabledActivitiesThrowAndDegrade() async {
        let gateway = MockActivityGateway()
        gateway.enabled = false
        let coordinator = LiveActivityCoordinator(gateway: gateway)
        await #expect(throws: LiveActivityError.activitiesDisabled) {
            try await coordinator.begin(attributes: Self.sampleAttributes(),
                                        initialState: Self.sampleState(phase: .walkingToStop))
        }
        #expect(!coordinator.isActive)
    }

    @Test func orphanActivitiesAreSweptOnBegin() async throws {
        let gateway = MockActivityGateway()
        gateway.preexistingIDs = ["orphan-from-crash"]
        let coordinator = LiveActivityCoordinator(gateway: gateway)
        try await coordinator.begin(attributes: Self.sampleAttributes(),
                                    initialState: Self.sampleState(phase: .walkingToStop))
        #expect(gateway.endedIDs.contains("orphan-from-crash"))
        #expect(coordinator.isActive)
    }

    @Test func identicalStatePushesAreDeduplicated() async throws {
        let gateway = MockActivityGateway()
        let coordinator = LiveActivityCoordinator(gateway: gateway)
        let state = Self.sampleState(phase: .waitingForBus)
        try await coordinator.begin(attributes: Self.sampleAttributes(),
                                    initialState: Self.sampleState(phase: .walkingToStop))
        await coordinator.push(state)
        await coordinator.push(state)   // identical: must be dropped
        await coordinator.push(state)   // identical: must be dropped
        #expect(gateway.updateCount == 1)
    }

    @Test func fullTripStaysWithinPushBudget() async throws {
        let gateway = MockActivityGateway()
        let coordinator = LiveActivityCoordinator(gateway: gateway)
        try await coordinator.begin(attributes: Self.sampleAttributes(),
                                    initialState: Self.sampleState(phase: .walkingToStop))
        for phase in [TripPhase.waitingForBus, .riding, .walkingToClass, .arrived] {
            await coordinator.push(Self.sampleState(phase: phase, steps: 100))
        }
        await coordinator.end(finalState: nil)
        // Design budget: 3–6 pushes per trip (begin + phase transitions).
        #expect(coordinator.pushCount <= 6)
        #expect(!coordinator.isActive)
    }

    @Test func tripSessionDrivesActivityThroughPhases() async throws {
        let gateway = MockActivityGateway()
        let coordinator = LiveActivityCoordinator(gateway: gateway)
        let session = TripSessionCoordinator(liveActivity: coordinator)

        let boarding = Date.now.addingTimeInterval(300)
        let legs = [
            RouteLeg(kind: .walk, line: nil, nodes: [NodeID("hall.6"), NodeID("stop.hall1")],
                     metres: 200, seconds: 150, boardingTime: nil),
            RouteLeg(kind: .shuttle, line: ShuttleLineID("loop-red"),
                     nodes: [NodeID("stop.hall1"), NodeID("stop.spms")],
                     metres: 900, seconds: 300, boardingTime: boarding),
            RouteLeg(kind: .walk, line: nil, nodes: [NodeID("stop.spms"), NodeID("bldg.spms")],
                     metres: 80, seconds: 60, boardingTime: nil),
        ]
        let route = Route(legs: legs, departureTime: .now,
                          arrivalTime: .now.addingTimeInterval(510),
                          totalWalkMetres: 280, exposedMetres: 280)

        try await session.start(route: route, summary: "Hall 6 → SPMS", nextClass: nil)
        #expect(session.phase == .walkingToStop)

        try await session.advance(to: .waitingForBus)
        try await session.advance(to: .riding)
        try await session.advance(to: .walkingToClass)
        try await session.advance(to: .arrived)

        #expect(!session.isActive)              // arrival auto-ends the trip
        #expect(coordinator.pushCount <= 6)     // budget holds end-to-end
        #expect(gateway.endedIDs.count == 1)
    }
}
