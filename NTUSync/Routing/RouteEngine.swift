import Foundation
import os

/// Thread-safe routing core. All mutable state (the route cache) is actor-
/// isolated; the graph and timetable are immutable values, so the search body
/// is a pure function running inside the actor with no suspension points —
/// reentrancy can never interleave two searches mid-flight.
actor RouteEngine {
    private let graph: CampusGraph
    private let timetable: ShuttleTimetable

    private var cache: [CacheKey: Route] = [:]
    private var cacheOrder: [CacheKey] = []
    private let cacheCapacity = 64

    init(graph: CampusGraph, timetable: ShuttleTimetable) {
        self.graph = graph
        self.timetable = timetable
    }

    // MARK: Public API

    func route(_ query: RouteQuery, useHeuristic: Bool = true) throws(RoutingError) -> Route {
        guard graph.nodes[query.origin] != nil else { throw .unknownNode(query.origin) }
        guard let goalNode = graph.nodes[query.destination] else { throw .unknownNode(query.destination) }

        let key = CacheKey(query: query, heuristic: useHeuristic)
        if let hit = cache[key] {
            Logger.routing.debug("cache hit \(query.origin) -> \(query.destination)")
            return hit
        }

        let clock = ContinuousClock()
        let start = clock.now
        guard let result = search(query: query, goal: goalNode, useHeuristic: useHeuristic) else {
            Logger.routing.error("no route \(query.origin) -> \(query.destination) profile=\(query.profile.id)")
            throw .noRouteFound
        }
        let elapsed = clock.now - start
        Logger.routing.debug("routed \(query.origin) -> \(query.destination) in \(elapsed) settled=\(result.settledCount)")

        let route = buildRoute(query: query, result: result)
        store(route, for: key)
        return route
    }

    func nearestNode(to coordinate: GeoPoint, where predicate: @Sendable (GraphNode) -> Bool = { _ in true }) -> NodeID? {
        graph.nearestNode(to: coordinate, where: predicate)?.id
    }

    // MARK: Search

    /// Search state is (node, on-board line): the same stop reached on foot,
    /// on Loop Red, or on Loop Blue has different downstream costs.
    private struct SearchState: Hashable {
        let node: NodeID
        let line: ShuttleLineID?
    }

    private struct HeapEntry: Comparable {
        let f: Double
        let g: Double
        let state: SearchState
        static func < (lhs: HeapEntry, rhs: HeapEntry) -> Bool { lhs.f < rhs.f }
        static func == (lhs: HeapEntry, rhs: HeapEntry) -> Bool { lhs.f == rhs.f }
    }

    private struct SearchResult {
        let goalState: SearchState
        let cost: [SearchState: Double]
        let predecessor: [SearchState: (state: SearchState, edge: GraphEdge)]
        let settledCount: Int
    }

    private func search(query: RouteQuery, goal: GraphNode, useHeuristic: Bool) -> SearchResult? {
        // Admissible heuristic: crow-flies distance over the fastest attainable
        // speed. Every edge's cost is >= length/vMax >= crowFlies/vMax.
        let vMax = max(query.profile.walkSpeedMetresPerSecond, timetable.shuttleSpeedMetresPerSecond)
        func h(_ node: NodeID) -> Double {
            guard useHeuristic, let n = graph.nodes[node] else { return 0 }
            return n.coordinate.distance(to: goal.coordinate) / vMax
        }

        let departurePoint = WeekTimePoint.from(query.departure)
        let origin = SearchState(node: query.origin, line: nil)
        var gScore: [SearchState: Double] = [origin: 0]
        var predecessor: [SearchState: (state: SearchState, edge: GraphEdge)] = [:]
        var settled: Set<SearchState> = []
        var heap = PriorityHeap<HeapEntry>()
        heap.push(HeapEntry(f: h(origin.node), g: 0, state: origin))

        while let entry = heap.pop() {
            if settled.contains(entry.state) { continue }  // lazy deletion
            settled.insert(entry.state)
            if entry.state.node == goal.id {
                return SearchResult(goalState: entry.state, cost: gScore, predecessor: predecessor, settledCount: settled.count)
            }
            let now = departurePoint.advanced(bySeconds: entry.g)
            for edge in graph.adjacency[entry.state.node] ?? [] {
                guard let edgeCost = cost(of: edge, from: entry.state, at: now, profile: query.profile) else { continue }
                let nextState = SearchState(node: edge.to, line: edge.kind == .shuttle ? edge.line : nil)
                let g = entry.g + edgeCost
                if g < gScore[nextState, default: .infinity] {
                    gScore[nextState] = g
                    predecessor[nextState] = (entry.state, edge)
                    heap.push(HeapEntry(f: g + h(edge.to), g: g, state: nextState))
                }
            }
        }
        return nil
    }

    /// Time-dependent edge cost in seconds, or nil when the edge is unusable
    /// (stairs under a step-free profile, shuttle line not in service).
    /// Waits are evaluated at arrival time; deliberately loitering for a
    /// cheaper service period is not modeled.
    private func cost(of edge: GraphEdge, from state: SearchState, at time: WeekTimePoint, profile: TravelProfile) -> Double? {
        switch edge.kind {
        case .shuttle:
            guard let line = edge.line else { return nil }
            let ride = timetable.rideSeconds(forEdgeLength: edge.lengthMetres)
            if state.line == line { return ride }                    // already on board
            guard let wait = timetable.expectedWaitSeconds(line: line, at: time) else { return nil }
            return wait + ride + profile.shuttleBoardingPenalty
        case .stairs where !profile.allowsStairs:
            return nil
        case .walk, .shelteredWalk, .stairs, .indoor:
            let base = edge.lengthMetres / profile.walkSpeedMetresPerSecond
            let slope = max(0, edge.elevationDelta / max(edge.lengthMetres, 1))
            let multiplier = 1
                + profile.rainAversion * edge.kind.rainExposure
                + profile.slopeAversion * slope
            return base * multiplier
        }
    }

    // MARK: Route assembly

    private func buildRoute(query: RouteQuery, result: SearchResult) -> Route {
        // Reconstruct the edge chain goal -> origin, then reverse.
        var chain: [(edge: GraphEdge, gAtEdgeStart: Double)] = []
        var cursor = result.goalState
        while let step = result.predecessor[cursor] {
            chain.append((step.edge, result.cost[step.state] ?? 0))
            cursor = step.state
        }
        chain.reverse()

        let departurePoint = WeekTimePoint.from(query.departure)
        var legs: [RouteLeg] = []
        var index = 0
        while index < chain.count {
            let head = chain[index]
            var nodes = [head.edge.from, head.edge.to]
            var metres = head.edge.lengthMetres
            var end = index
            while end + 1 < chain.count,
                  chain[end + 1].edge.kind == head.edge.kind,
                  chain[end + 1].edge.line == head.edge.line {
                end += 1
                nodes.append(chain[end].edge.to)
                metres += chain[end].edge.lengthMetres
            }
            let gStart = head.gAtEdgeStart
            let gEnd = end + 1 < chain.count
                ? chain[end + 1].gAtEdgeStart
                : (result.cost[result.goalState] ?? gStart)

            var boardingTime: Date?
            if head.edge.kind == .shuttle, let line = head.edge.line {
                let wait = timetable.expectedWaitSeconds(line: line, at: departurePoint.advanced(bySeconds: gStart)) ?? 0
                boardingTime = query.departure.addingTimeInterval(gStart + wait)
            }
            legs.append(RouteLeg(
                kind: head.edge.kind,
                line: head.edge.line,
                nodes: nodes,
                metres: metres,
                seconds: gEnd - gStart,
                boardingTime: boardingTime
            ))
            index = end + 1
        }

        let totalSeconds = result.cost[result.goalState] ?? 0
        let footMetres = legs.filter { $0.kind.isFootTravel }.reduce(0) { $0 + $1.metres }
        let exposed = chain
            .map { $0.edge.lengthMetres * $0.edge.kind.rainExposure }
            .reduce(0, +)

        return Route(
            legs: legs,
            departureTime: query.departure,
            arrivalTime: query.departure.addingTimeInterval(totalSeconds),
            totalWalkMetres: footMetres,
            exposedMetres: exposed
        )
    }

    // MARK: Cache (LRU by insertion, minute-bucketed departure)

    private struct CacheKey: Hashable {
        let origin: NodeID
        let destination: NodeID
        let profileID: String
        let minuteBucket: Int
        let heuristic: Bool

        init(query: RouteQuery, heuristic: Bool) {
            origin = query.origin
            destination = query.destination
            profileID = query.profile.id
            minuteBucket = Int(query.departure.timeIntervalSinceReferenceDate / 60)
            self.heuristic = heuristic
        }
    }

    private func store(_ route: Route, for key: CacheKey) {
        if cache[key] == nil {
            cacheOrder.append(key)
            if cacheOrder.count > cacheCapacity {
                cache.removeValue(forKey: cacheOrder.removeFirst())
            }
        }
        cache[key] = route
    }
}
