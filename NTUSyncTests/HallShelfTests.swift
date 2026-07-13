import Testing
import Foundation
@testable import NTUSync

struct HallShelfPlannerTests {

    static func lunchtime() -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = 12; components.minute = 30
        return Calendar.current.date(from: components)!
    }

    @Test func shelfFromHallSixCoversEverySlotWithReachableOptions() async throws {
        let graph = try CampusGraph.loadBundled()
        let timetable = try ShuttleTimetable.loadBundled()
        let amenities = try AmenityDirectory.loadBundled()
        let engine = RouteEngine(graph: graph, timetable: timetable)

        let bench = BenchCandidate(graphNodeID: NodeID("bldg.hive"),
                                   hasPower: true, isSheltered: true, note: "Hive pod")

        let items = await HallShelfPlanner.shelf(
            from: NodeID("hall.6"), at: Self.lunchtime(),
            benches: [bench], amenities: amenities,
            graph: graph, engine: engine
        )

        // At lunchtime with the curated dataset every slot should resolve.
        #expect(items.count == HallShelfPlanner.Slot.allCases.count)
        #expect(Set(items.map(\.slot)).count == items.count, "one item per slot")
        for item in items {
            #expect(item.walkMinutes >= 1)
            #expect(Double(item.walkMinutes) <= HallShelfPlanner.maxWalkMinutes)
            #expect(graph.nodes[item.destination] != nil,
                    "\(item.title) points at unknown node \(item.destination)")
            #expect(item.destination != NodeID("hall.6"))
        }
    }

    @Test func emptyBenchListStillYieldsAmenitySlots() async throws {
        let graph = try CampusGraph.loadBundled()
        let timetable = try ShuttleTimetable.loadBundled()
        let amenities = try AmenityDirectory.loadBundled()
        let engine = RouteEngine(graph: graph, timetable: timetable)

        let items = await HallShelfPlanner.shelf(
            from: NodeID("hall.1"), at: Self.lunchtime(),
            benches: [], amenities: amenities,
            graph: graph, engine: engine
        )
        #expect(!items.contains { $0.slot == .bench })
        #expect(items.contains { $0.slot == .food })
    }

    @Test func unknownHomeNodeYieldsEmptyShelf() async throws {
        let graph = try CampusGraph.loadBundled()
        let timetable = try ShuttleTimetable.loadBundled()
        let amenities = try AmenityDirectory.loadBundled()
        let engine = RouteEngine(graph: graph, timetable: timetable)

        let items = await HallShelfPlanner.shelf(
            from: NodeID("hall.nonexistent"), at: Self.lunchtime(),
            benches: [], amenities: amenities,
            graph: graph, engine: engine
        )
        #expect(items.isEmpty)
    }
}
