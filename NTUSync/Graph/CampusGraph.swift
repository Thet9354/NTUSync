import Foundation
import os

nonisolated enum GraphLoadingError: Error {
    case resourceMissing(String)
    case malformed(String)
}

/// Immutable campus topology. Built once from the bundled JSON document and
/// shared freely across actors — deep immutability is what makes the routing
/// layer thread-safe without locks.
nonisolated struct CampusGraph: Sendable {
    let nodes: [NodeID: GraphNode]
    let adjacency: [NodeID: [GraphEdge]]

    var edgeCount: Int { adjacency.values.reduce(0) { $0 + $1.count } }
    var allEdges: [GraphEdge] { adjacency.values.flatMap(\.self) }

    init(nodes: [GraphNode], edges: [GraphEdge]) {
        self.nodes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        self.adjacency = Dictionary(grouping: edges, by: \.from)
    }

    // MARK: Loading

    private struct Document: Codable {
        struct Node: Codable {
            let id: NodeID
            let displayName: String?
            let latitude: Double
            let longitude: Double
            let elevation: Double
            let isIndoor: Bool
        }
        struct Edge: Codable {
            let from: NodeID
            let to: NodeID
            let kind: EdgeKind
            let lengthMetres: Double
            let elevationDelta: Double
            let line: ShuttleLineID?
        }
        let formatVersion: Int
        let nodes: [Node]
        let edges: [Edge]
    }

    static func loadBundled(_ bundle: Bundle = .main) throws -> CampusGraph {
        guard let url = bundle.url(forResource: "CampusGraph", withExtension: "json") else {
            Logger.routing.fault("CampusGraph.json missing from bundle")
            throw GraphLoadingError.resourceMissing("CampusGraph.json")
        }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        guard document.formatVersion == 1 else {
            throw GraphLoadingError.malformed("unsupported formatVersion \(document.formatVersion)")
        }
        let graph = CampusGraph(
            nodes: document.nodes.map {
                GraphNode(
                    id: $0.id,
                    coordinate: GeoPoint(latitude: $0.latitude, longitude: $0.longitude),
                    elevation: $0.elevation,
                    isIndoor: $0.isIndoor,
                    displayName: $0.displayName
                )
            },
            edges: document.edges.map {
                GraphEdge(
                    from: $0.from,
                    to: $0.to,
                    kind: $0.kind,
                    lengthMetres: $0.lengthMetres,
                    elevationDelta: $0.elevationDelta,
                    line: $0.line
                )
            }
        )
        Logger.routing.info("Loaded campus graph: \(graph.nodes.count) nodes, \(graph.edgeCount) edges")
        return graph
    }

    // MARK: Queries

    func nearestNode(
        to coordinate: GeoPoint,
        where predicate: (GraphNode) -> Bool = { _ in true }
    ) -> GraphNode? {
        nodes.values
            .filter(predicate)
            .min { coordinate.distance(to: $0.coordinate) < coordinate.distance(to: $1.coordinate) }
    }

    var namedNodes: [GraphNode] {
        nodes.values
            .filter { $0.displayName != nil }
            .sorted { ($0.displayName ?? "") < ($1.displayName ?? "") }
    }

    // MARK: Validation (the data-file contract; exercised by unit tests)

    func validationIssues(timetable: ShuttleTimetable? = nil) -> [String] {
        var issues: [String] = []

        for edge in allEdges {
            if nodes[edge.from] == nil { issues.append("edge \(edge.from)->\(edge.to): unknown origin node") }
            if nodes[edge.to] == nil { issues.append("edge \(edge.from)->\(edge.to): unknown destination node") }
            if edge.kind == .shuttle && edge.line == nil {
                issues.append("shuttle edge \(edge.from)->\(edge.to) has no line")
            }
            if edge.kind != .shuttle && edge.line != nil {
                issues.append("non-shuttle edge \(edge.from)->\(edge.to) carries a line")
            }
            if let from = nodes[edge.from], let to = nodes[edge.to] {
                let crowFlies = from.coordinate.distance(to: to.coordinate)
                if edge.lengthMetres + 0.5 < crowFlies || edge.lengthMetres > 3 * max(crowFlies, 1) {
                    issues.append("edge \(edge.from)->\(edge.to): length \(edge.lengthMetres)m outside sanity band for \(crowFlies)m crow-flies")
                }
                let expectedDelta = to.elevation - from.elevation
                if abs(edge.elevationDelta - expectedDelta) > 2 {
                    issues.append("edge \(edge.from)->\(edge.to): elevationDelta \(edge.elevationDelta) disagrees with node elevations")
                }
            }
        }

        // Foot-network strong connectivity: every node must be reachable on foot.
        if let start = nodes.keys.sorted(by: { $0.rawValue < $1.rawValue }).first {
            let reached = reachableOnFoot(from: start)
            for id in nodes.keys where !reached.contains(id) {
                issues.append("node \(id) unreachable on foot from \(start)")
            }
        }

        if let timetable {
            for edge in allEdges where edge.kind == .shuttle {
                if let line = edge.line, timetable.line(line) == nil {
                    issues.append("shuttle edge \(edge.from)->\(edge.to): line \(line) missing from timetable")
                }
            }
        }

        return issues
    }

    private func reachableOnFoot(from start: NodeID) -> Set<NodeID> {
        var seen: Set<NodeID> = [start]
        var frontier = [start]
        while let node = frontier.popLast() {
            for edge in adjacency[node] ?? [] where edge.kind.isFootTravel && !seen.contains(edge.to) {
                seen.insert(edge.to)
                frontier.append(edge.to)
            }
        }
        return seen
    }
}
