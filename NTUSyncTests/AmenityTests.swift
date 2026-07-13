import Testing
import Foundation
@testable import NTUSync

struct AmenityTests {

    @Test func bundledAmenitiesReferenceRealGraphNodes() throws {
        let directory = try AmenityDirectory.loadBundled()
        let graph = try CampusGraph.loadBundled()
        #expect(directory.amenities.count >= 15)
        for amenity in directory.amenities {
            #expect(graph.nodes[amenity.graphNodeID] != nil,
                    "amenity \(amenity.id) references unknown node \(amenity.graphNodeID)")
        }
        // IDs must be unique — they key the UI.
        #expect(Set(directory.amenities.map(\.id)).count == directory.amenities.count)
    }

    @Test func openingHoursIncludingMidnightWrap() {
        let daytime = Amenity(id: "a", name: "A", category: .food, graphNodeID: NodeID("n"),
                              latitude: 0, longitude: 0, openMinute: 420, closeMinute: 1260, note: nil)
        #expect(daytime.isOpen(atMinuteOfDay: 720))       // noon
        #expect(!daytime.isOpen(atMinuteOfDay: 300))      // 5 am
        #expect(!daytime.isOpen(atMinuteOfDay: 1260))     // exactly at close

        let supper = Amenity(id: "b", name: "B", category: .supper, graphNodeID: NodeID("n"),
                             latitude: 0, longitude: 0, openMinute: 1080, closeMinute: 120, note: nil)
        #expect(supper.isOpen(atMinuteOfDay: 1380))       // 11 pm
        #expect(supper.isOpen(atMinuteOfDay: 60))         // 1 am (wrapped)
        #expect(!supper.isOpen(atMinuteOfDay: 720))       // noon

        let always = Amenity(id: "c", name: "C", category: .atm, graphNodeID: NodeID("n"),
                             latitude: 0, longitude: 0, openMinute: nil, closeMinute: nil, note: nil)
        #expect(always.isOpen(atMinuteOfDay: 0))
    }

    @Test func gapPlannerRanksNearbyOpenOptions() async throws {
        let graph = try CampusGraph.loadBundled()
        let timetable = try ShuttleTimetable.loadBundled()
        let amenities = try AmenityDirectory.loadBundled()
        let engine = RouteEngine(graph: graph, timetable: timetable)

        // Tuesday 12:30 lunch gap at SPMS.
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 8
        components.hour = 12; components.minute = 30
        let gapStart = Calendar.current.date(from: components)!

        let benches = [BenchCandidate(graphNodeID: NodeID("bldg.spms"), hasPower: true,
                                      isSheltered: true, note: "SPMS bench")]
        let suggestions = await GapPlanner.suggestions(
            from: NodeID("bldg.spms"), gapStart: gapStart, gapMinutes: 90,
            benches: benches, amenities: amenities, graph: graph, engine: engine
        )
        #expect(!suggestions.isEmpty)
        #expect(suggestions.count <= 4)
        // Everything suggested must be walkable within the cap.
        #expect(suggestions.allSatisfy { $0.walkMinutes <= Int(GapPlanner.maxWalkMinutes) })
        // Lunch window: at least one food-ish option should surface.
        #expect(suggestions.contains { [.food, .cafe, .supper].contains($0.category ?? .atm) })
    }

    @Test func gapPlannerRejectsShortGaps() async throws {
        let graph = try CampusGraph.loadBundled()
        let timetable = try ShuttleTimetable.loadBundled()
        let amenities = try AmenityDirectory.loadBundled()
        let engine = RouteEngine(graph: graph, timetable: timetable)
        let suggestions = await GapPlanner.suggestions(
            from: NodeID("bldg.spms"), gapStart: .now, gapMinutes: 15,
            benches: [], amenities: amenities, graph: graph, engine: engine
        )
        #expect(suggestions.isEmpty)
    }
}
