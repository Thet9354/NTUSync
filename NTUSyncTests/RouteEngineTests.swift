import Testing
import Foundation
@testable import NTUSync

struct RouteEngineTests {

    static func makeEngine() throws -> (RouteEngine, CampusGraph) {
        let graph = try CampusGraph.loadBundled()
        let timetable = try ShuttleTimetable.loadBundled()
        return (RouteEngine(graph: graph, timetable: timetable), graph)
    }

    static func date(weekdayHint: String = "tue", hour: Int, minute: Int) -> Date {
        // 2026-09-08 is a Tuesday; 2026-09-13 a Sunday (local calendar).
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = weekdayHint == "sun" ? 13 : 8
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    /// Deterministic LCG so the property test is reproducible.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    @Test func aStarCostEqualsDijkstraOnRandomPairs() async throws {
        let (engine, graph) = try Self.makeEngine()
        let nodes = graph.nodes.keys.sorted { $0.rawValue < $1.rawValue }
        var rng = SeededGenerator(state: 42)
        let departure = Self.date(hour: 8, minute: 20)

        for _ in 0..<150 {
            let origin = nodes.randomElement(using: &rng)!
            let destination = nodes.randomElement(using: &rng)!
            guard origin != destination else { continue }
            let query = RouteQuery(origin: origin, destination: destination,
                                   departure: departure, profile: .fastest)
            let aStar = try await engine.route(query, useHeuristic: true)
            let dijkstra = try await engine.route(query, useHeuristic: false)
            #expect(abs(aStar.totalSeconds - dijkstra.totalSeconds) < 0.01,
                    "\(origin) -> \(destination): A* \(aStar.totalSeconds)s != Dijkstra \(dijkstra.totalSeconds)s")
        }
    }

    @Test func routeLegsFormAConnectedChain() async throws {
        let (engine, _) = try Self.makeEngine()
        let query = RouteQuery(origin: NodeID("hall.6"), destination: NodeID("bldg.spms"),
                               departure: Self.date(hour: 8, minute: 20), profile: .fastest)
        let route = try await engine.route(query)
        #expect(route.legs.first?.nodes.first == NodeID("hall.6"))
        #expect(route.legs.last?.nodes.last == NodeID("bldg.spms"))
        for (previous, next) in zip(route.legs, route.legs.dropFirst()) {
            #expect(previous.nodes.last == next.nodes.first, "legs must connect end-to-end")
        }
        #expect(route.arrivalTime > route.departureTime)
    }

    @Test func noShuttleLegsWhenServiceIsClosed() async throws {
        let (engine, _) = try Self.makeEngine()
        // 02:30 — both loops are out of service; the foot network must carry the trip.
        let query = RouteQuery(origin: NodeID("hall.1"), destination: NodeID("bldg.spms"),
                               departure: Self.date(hour: 2, minute: 30), profile: .fastest)
        let route = try await engine.route(query)
        #expect(!route.legs.contains { $0.kind == .shuttle })
    }

    @Test func laterDepartureNeverArrivesEarlier() async throws {
        let (engine, _) = try Self.makeEngine()
        let base = Self.date(hour: 8, minute: 20)
        let later = Self.date(hour: 8, minute: 30)
        for profile in [TravelProfile.fastest, .lazy] {
            let query1 = RouteQuery(origin: NodeID("hall.6"), destination: NodeID("bldg.wkw"),
                                    departure: base, profile: profile)
            let query2 = RouteQuery(origin: NodeID("hall.6"), destination: NodeID("bldg.wkw"),
                                    departure: later, profile: profile)
            let route1 = try await engine.route(query1)
            let route2 = try await engine.route(query2)
            #expect(route2.arrivalTime >= route1.arrivalTime)
        }
    }

    @Test func stepFreeProfileAvoidsStairs() async throws {
        let (engine, _) = try Self.makeEngine()
        // The North Spine underpass is reached via stairs; step-free must not use it.
        let query = RouteQuery(origin: NodeID("bldg.northspine"), destination: NodeID("bldg.sbs"),
                               departure: Self.date(hour: 10, minute: 0), profile: .accessible)
        let route = try await engine.route(query)
        #expect(!route.legs.contains { $0.kind == .stairs })
    }

    @Test func rainSafeProfileReducesExposure() async throws {
        let (engine, _) = try Self.makeEngine()
        let departure = Self.date(hour: 14, minute: 0)
        let fastest = try await engine.route(RouteQuery(
            origin: NodeID("bldg.lwn"), destination: NodeID("bldg.spms"),
            departure: departure, profile: .fastest))
        let rainSafe = try await engine.route(RouteQuery(
            origin: NodeID("bldg.lwn"), destination: NodeID("bldg.spms"),
            departure: departure, profile: .rainSafe))
        #expect(rainSafe.exposedMetres <= fastest.exposedMetres)
    }

    @Test func unknownNodeThrows() async throws {
        let (engine, _) = try Self.makeEngine()
        let query = RouteQuery(origin: NodeID("bldg.nonexistent"), destination: NodeID("bldg.spms"),
                               departure: .now, profile: .fastest)
        await #expect(throws: RoutingError.unknownNode(NodeID("bldg.nonexistent"))) {
            _ = try await engine.route(query)
        }
    }
}
