import Testing
import Foundation
@testable import NTUSync

/// The contract on the bundled data files (design spec §1.6).
struct CampusGraphValidationTests {

    @Test func bundledGraphPassesAllIntegrityChecks() throws {
        let graph = try CampusGraph.loadBundled()
        let timetable = try ShuttleTimetable.loadBundled()
        let issues = graph.validationIssues(timetable: timetable)
        #expect(issues.isEmpty, "graph data issues: \(issues.joined(separator: "; "))")
    }

    @Test func graphHasExpectedShape() throws {
        let graph = try CampusGraph.loadBundled()
        #expect(graph.nodes.count >= 20)
        #expect(graph.edgeCount >= 60)
        // Both loop directions must exist.
        let lines = Set(graph.allEdges.compactMap(\.line))
        #expect(lines.contains(ShuttleLineID("loop-red")))
        #expect(lines.contains(ShuttleLineID("loop-blue")))
        // At least one GPS-denied node for the dead-reckoning path.
        #expect(graph.nodes.values.contains { $0.isIndoor })
    }

    @Test func nearestNodeFindsIndoorAndOutdoorNodes() throws {
        let graph = try CampusGraph.loadBundled()
        let nearHive = GeoPoint(latitude: 1.34445, longitude: 103.68360)
        let nearest = graph.nearestNode(to: nearHive) { !$0.isIndoor }
        #expect(nearest?.id == NodeID("bldg.hive"))
    }
}
