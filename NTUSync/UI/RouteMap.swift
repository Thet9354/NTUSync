import SwiftUI
import MapKit

/// Shared geometry + styling for drawing a Route on MapKit.
nonisolated struct RouteMapGeometry {
    struct Segment {
        let kind: EdgeKind
        let coordinates: [CLLocationCoordinate2D]
        let cumulativeStart: Double   // metres from route start
        let length: Double
    }

    let segments: [Segment]
    let totalMetres: Double
    let origin: CLLocationCoordinate2D?
    let destination: CLLocationCoordinate2D?

    init(route: Route, graph: CampusGraph) {
        var segments: [Segment] = []
        var cumulative = 0.0
        for leg in route.legs {
            let coords = leg.nodes.compactMap { graph.nodes[$0]?.coordinate }
                .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            guard coords.count >= 2 else { continue }
            segments.append(Segment(
                kind: leg.kind, coordinates: coords,
                cumulativeStart: cumulative, length: leg.metres
            ))
            cumulative += leg.metres
        }
        self.segments = segments
        self.totalMetres = cumulative
        self.origin = segments.first?.coordinates.first
        self.destination = segments.last?.coordinates.last
    }

    /// Coordinates of a segment clipped to a global reveal distance, with the
    /// last point linearly interpolated — drives the draw-in animation.
    func revealedCoordinates(of segment: Segment, upTo revealMetres: Double) -> [CLLocationCoordinate2D] {
        let local = revealMetres - segment.cumulativeStart
        guard local > 0 else { return [] }
        if local >= segment.length { return segment.coordinates }

        let fraction = local / segment.length
        let points = segment.coordinates
        let scaled = fraction * Double(points.count - 1)
        let whole = min(points.count - 2, Int(scaled))
        let partial = scaled - Double(whole)
        let a = points[whole], b = points[whole + 1]
        let interpolated = CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * partial,
            longitude: a.longitude + (b.longitude - a.longitude) * partial
        )
        return Array(points.prefix(whole + 1)) + [interpolated]
    }
}

extension EdgeKind {
    var mapColor: Color {
        switch self {
        case .walk: .blue
        case .shelteredWalk: .teal
        case .stairs: .orange
        case .indoor: .purple
        case .shuttle: Brand.red
        }
    }
}

/// Animated route preview embedded in the planner and timetable results:
/// the route draws itself in while the camera frames it.
struct RouteMapPreview: View {
    @Environment(AppEnvironment.self) private var env
    let route: Route

    @State private var revealFraction: Double = 0

    var body: some View {
        let geometry = RouteMapGeometry(route: route, graph: env.graph)
        Map(interactionModes: [.zoom, .pan]) {
            ForEach(Array(geometry.segments.enumerated()), id: \.offset) { _, segment in
                let coords = geometry.revealedCoordinates(
                    of: segment, upTo: revealFraction * geometry.totalMetres
                )
                if coords.count >= 2 {
                    MapPolyline(coordinates: coords)
                        .stroke(segment.kind.mapColor, style: StrokeStyle(
                            lineWidth: 5, lineCap: .round, lineJoin: .round,
                            dash: segment.kind == .shuttle ? [] : [1, 7]
                        ))
                }
            }
            if let origin = geometry.origin {
                Annotation("", coordinate: origin) {
                    Circle().fill(.white)
                        .stroke(Brand.navyDeep, lineWidth: 3)
                        .frame(width: 14, height: 14)
                }
            }
            if let destination = geometry.destination, revealFraction > 0.95 {
                Marker(route.destination.map(env.displayName(for:)) ?? "Destination",
                       systemImage: "flag.checkered", coordinate: destination)
                .tint(Brand.red)
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .listRowInsets(EdgeInsets())
        .task(id: route) {
            revealFraction = 0
            // ~1.1 s draw-in at 30 fps.
            for step in 1...32 {
                try? await Task.sleep(for: .milliseconds(35))
                revealFraction = Double(step) / 32
            }
        }
    }
}
