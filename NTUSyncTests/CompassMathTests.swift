import Testing
import Foundation
@testable import NTUSync

struct CompassMathTests {

    /// Campus-scale grid: 0.001° latitude ≈ 111 m.
    static let origin = GeoPoint(latitude: 1.3400, longitude: 103.6800)
    static func point(_ dLat: Double, _ dLon: Double) -> GeoPoint {
        GeoPoint(latitude: Self.origin.latitude + dLat, longitude: Self.origin.longitude + dLon)
    }

    static func near(_ a: Double, _ b: Double, tolerance: Double = 0.5) -> Bool {
        abs(a - b) < tolerance
    }

    @Test func bearingCardinalDirections() {
        #expect(Self.near(CompassMath.bearing(from: Self.origin, to: Self.point(0.001, 0)), 0))
        #expect(Self.near(CompassMath.bearing(from: Self.origin, to: Self.point(0, 0.001)), 90))
        #expect(Self.near(CompassMath.bearing(from: Self.origin, to: Self.point(-0.001, 0)), 180))
        #expect(Self.near(CompassMath.bearing(from: Self.origin, to: Self.point(0, -0.001)), 270))
        #expect(Self.near(CompassMath.bearing(from: Self.origin, to: Self.point(0.001, 0.001)), 45, tolerance: 1))
    }

    @Test func relativeAngleWrapsAcrossNorth() {
        #expect(CompassMath.relativeAngle(bearing: 10, heading: 350) == 20)
        #expect(CompassMath.relativeAngle(bearing: 350, heading: 10) == -20)
        #expect(CompassMath.relativeAngle(bearing: 90, heading: 90) == 0)
        // Directly behind normalises to +180, never -180.
        #expect(CompassMath.relativeAngle(bearing: 270, heading: 90) == 180)
        #expect(CompassMath.relativeAngle(bearing: 90, heading: 270) == 180)
    }

    @Test func arrowGlyphOctants() {
        #expect(CompassMath.arrowGlyph(relativeAngle: 0) == "↑")
        #expect(CompassMath.arrowGlyph(relativeAngle: 45) == "↗")
        #expect(CompassMath.arrowGlyph(relativeAngle: 90) == "→")
        #expect(CompassMath.arrowGlyph(relativeAngle: 135) == "↘")
        #expect(CompassMath.arrowGlyph(relativeAngle: 180) == "↓")
        #expect(CompassMath.arrowGlyph(relativeAngle: -135) == "↙")
        #expect(CompassMath.arrowGlyph(relativeAngle: -90) == "←")
        #expect(CompassMath.arrowGlyph(relativeAngle: -45) == "↖")
        // Octant boundaries round to the nearer glyph.
        #expect(CompassMath.arrowGlyph(relativeAngle: 21) == "↑")
        #expect(CompassMath.arrowGlyph(relativeAngle: 23) == "↗")
    }

    @Test func distanceTextScales() {
        #expect(CompassMath.distanceText(metres: 140.3) == "140 m")
        #expect(CompassMath.distanceText(metres: 949) == "949 m")
        #expect(CompassMath.distanceText(metres: 1250) == "1.2 km")
    }

    @Test func headingReliability() {
        #expect(CompassMath.isHeadingReliable(accuracyDegrees: 5))
        #expect(CompassMath.isHeadingReliable(accuracyDegrees: 30))
        #expect(!CompassMath.isHeadingReliable(accuracyDegrees: 31))
        #expect(!CompassMath.isHeadingReliable(accuracyDegrees: -1))   // invalid
    }

    // MARK: Next-checkpoint selection

    /// A ─ B ─ C (walk leg) then C ─ D ─ E (shuttle leg): checkpoints C and E.
    /// Nodes run due north, ~111 m apart.
    static let coordinates: [NodeID: GeoPoint] = [
        NodeID("a"): point(0.000, 0), NodeID("b"): point(0.001, 0),
        NodeID("c"): point(0.002, 0), NodeID("d"): point(0.003, 0),
        NodeID("e"): point(0.004, 0),
    ]

    static var legs: [RouteLeg] {
        [RouteLeg(kind: .walk, line: nil,
                  nodes: [NodeID("a"), NodeID("b"), NodeID("c")],
                  metres: 222, seconds: 180, boardingTime: nil),
         RouteLeg(kind: .shuttle, line: ShuttleLineID("loop-red"),
                  nodes: [NodeID("c"), NodeID("d"), NodeID("e")],
                  metres: 222, seconds: 120, boardingTime: nil)]
    }

    static func target(from position: GeoPoint) -> CompassTarget? {
        CompassMath.nextCheckpoint(legs: legs, position: position) { coordinates[$0] }
    }

    @Test func targetsFirstLegEndFromTheStart() throws {
        let target = try #require(Self.target(from: Self.point(0.0001, 0)))
        #expect(target.nodeID == NodeID("c"))
        #expect(Self.near(target.bearingDegrees, 0))
        #expect(abs(target.distanceMetres - 211) < 5)   // ~222 m minus the 11 m walked
    }

    @Test func midLegStillTargetsThatLegsEnd() throws {
        let target = try #require(Self.target(from: Self.point(0.001, 0.0001)))
        #expect(target.nodeID == NodeID("c"))
    }

    @Test func arrivingAtACheckpointAdvancesToTheNext() throws {
        // Within the 25 m arrival radius of C → arrow moves on to E.
        let target = try #require(Self.target(from: Self.point(0.002, 0.0001)))
        #expect(target.nodeID == NodeID("e"))
    }

    @Test func finalCheckpointNeverAdvancesPastDestination() throws {
        let target = try #require(Self.target(from: Self.point(0.004, 0.0001)))
        #expect(target.nodeID == NodeID("e"))
    }

    @Test func emptyRouteYieldsNoTarget() {
        #expect(CompassMath.nextCheckpoint(legs: [], position: Self.origin) { Self.coordinates[$0] } == nil)
    }

    @Test func unknownCoordinatesAreSkippedSafely() {
        // No node resolves → no chain → nil, not a crash.
        let target = CompassMath.nextCheckpoint(legs: Self.legs, position: Self.origin) { _ in nil }
        #expect(target == nil)
    }
}
