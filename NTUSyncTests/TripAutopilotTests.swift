import Testing
import Foundation
@testable import NTUSync

struct TripAutopilotTests {

    // Synthetic north-running route: walk A->B, shuttle B->C->D, walk D->E.
    // 0.001 degrees latitude ~= 111 m.
    static let coordinates: [NodeID: GeoPoint] = [
        NodeID("A"): GeoPoint(latitude: 1.0000, longitude: 103.0),
        NodeID("B"): GeoPoint(latitude: 1.0018, longitude: 103.0),
        NodeID("C"): GeoPoint(latitude: 1.0050, longitude: 103.0),
        NodeID("D"): GeoPoint(latitude: 1.0090, longitude: 103.0),
        NodeID("E"): GeoPoint(latitude: 1.0099, longitude: 103.0),
    ]

    static func locate(_ node: NodeID) -> GeoPoint? { coordinates[node] }

    static func makeRoute() -> Route {
        let legs = [
            RouteLeg(kind: .walk, line: nil, nodes: [NodeID("A"), NodeID("B")],
                     metres: 200, seconds: 150, boardingTime: nil),
            RouteLeg(kind: .shuttle, line: ShuttleLineID("loop-red"),
                     nodes: [NodeID("B"), NodeID("C"), NodeID("D")],
                     metres: 800, seconds: 240, boardingTime: .now.addingTimeInterval(300)),
            RouteLeg(kind: .walk, line: nil, nodes: [NodeID("D"), NodeID("E")],
                     metres: 100, seconds: 75, boardingTime: nil),
        ]
        return Route(legs: legs, departureTime: .now, arrivalTime: .now.addingTimeInterval(465),
                     totalWalkMetres: 300, exposedMetres: 300)
    }

    @Test func extractsStopsFromRoute() {
        let autopilot = TripAutopilot(route: Self.makeRoute())
        #expect(autopilot.boardingStop == NodeID("B"))
        #expect(autopilot.alightingStop == NodeID("D"))
        #expect(autopilot.downstreamShuttleStops == [NodeID("C"), NodeID("D")])
    }

    @Test func arrivingAtBoardingStopTriggersWaiting() {
        let autopilot = TripAutopilot(route: Self.makeRoute())
        let nearB = GeoPoint(latitude: 1.00182, longitude: 103.0)   // ~2 m from B
        let next = autopilot.suggestedTransition(from: .walkingToStop, fix: nearB,
                                                 accuracy: 10, locate: Self.locate)
        #expect(next == .waitingForBus)
    }

    @Test func poorAccuracyNeverTriggersTransitions() {
        let autopilot = TripAutopilot(route: Self.makeRoute())
        let nearB = GeoPoint(latitude: 1.0018, longitude: 103.0)
        let next = autopilot.suggestedTransition(from: .walkingToStop, fix: nearB,
                                                 accuracy: 120, locate: Self.locate)
        #expect(next == nil)
    }

    @Test func reachingDownstreamStopMeansRiding() {
        let autopilot = TripAutopilot(route: Self.makeRoute())
        let nearC = GeoPoint(latitude: 1.00502, longitude: 103.0)
        let next = autopilot.suggestedTransition(from: .waitingForBus, fix: nearC,
                                                 accuracy: 15, locate: Self.locate)
        #expect(next == .riding)
    }

    @Test func stillAtBoardingStopIsNotRiding() {
        let autopilot = TripAutopilot(route: Self.makeRoute())
        let atB = GeoPoint(latitude: 1.0018, longitude: 103.0)
        let next = autopilot.suggestedTransition(from: .waitingForBus, fix: atB,
                                                 accuracy: 15, locate: Self.locate)
        #expect(next == nil)
    }

    @Test func alightingStopEndsTheRide() {
        let autopilot = TripAutopilot(route: Self.makeRoute())
        let nearD = GeoPoint(latitude: 1.00898, longitude: 103.0)
        let next = autopilot.suggestedTransition(from: .riding, fix: nearD,
                                                 accuracy: 20, locate: Self.locate)
        #expect(next == .walkingToClass)
    }

    @Test func destinationCompletesTheTrip() {
        let autopilot = TripAutopilot(route: Self.makeRoute())
        let nearE = GeoPoint(latitude: 1.00992, longitude: 103.0)
        let next = autopilot.suggestedTransition(from: .walkingToClass, fix: nearE,
                                                 accuracy: 10, locate: Self.locate)
        #expect(next == .arrived)
    }

    @Test func projectionMapsFixToArcLength() {
        let autopilot = TripAutopilot(route: Self.makeRoute())
        // At node C: 200 m walk leg + half of the 800 m shuttle leg = ~600 m.
        let atC = GeoPoint(latitude: 1.0050, longitude: 103.0)
        let along = autopilot.projectOntoRoute(fix: atC, locate: Self.locate)
        #expect(along != nil)
        #expect(abs((along ?? 0) - 600) < 1)
    }

    @Test func offCorridorFixDoesNotProject() {
        let autopilot = TripAutopilot(route: Self.makeRoute())
        // ~550 m east of the route corridor.
        let farAway = GeoPoint(latitude: 1.005, longitude: 103.005)
        #expect(autopilot.projectOntoRoute(fix: farAway, locate: Self.locate) == nil)
    }
}
