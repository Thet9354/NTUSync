import SwiftUI

/// NTUSync brand palette, derived from the app icon: a navy gradient with a
/// red destination pin and white route path.
enum Brand {
    static let navyDeep = Color(red: 0.04, green: 0.09, blue: 0.24)   // ~#0A1730
    static let navy = Color(red: 0.11, green: 0.22, blue: 0.44)       // ~#1C3870
    static let red = Color(red: 0.84, green: 0.19, blue: 0.24)        // ~#D5303D

    /// The full-bleed navy gradient used on the splash and onboarding.
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [navyDeep, navy],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// A SwiftUI recreation of the app icon's route glyph: a stroked "N"-shaped
/// path connecting a white origin node (bottom-left) to a red destination
/// pin (top-right). Scales to fill its frame.
struct BrandMark: View {
    /// 0…1 draw progress, used to animate the path stroking itself in.
    var progress: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let line = side * 0.14
            let node = side * 0.19

            // Route endpoints/corners in a unit square, matching the icon.
            let origin = point(0.28, 0.76, side)
            let midLow = point(0.28, 0.44, side)
            let midHigh = point(0.60, 0.52, side)
            let destination = point(0.60, 0.28, side)

            ZStack {
                // The white route path (origin → up → diagonal → up to pin).
                RoutePath(points: [origin, midLow, midHigh, destination])
                    .trim(from: 0, to: progress)
                    .stroke(
                        .white,
                        style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
                    )

                // Origin node: white ring with navy core.
                Circle()
                    .fill(.white)
                    .frame(width: node, height: node)
                    .overlay(
                        Circle()
                            .fill(Brand.navyDeep)
                            .frame(width: node * 0.42, height: node * 0.42)
                    )
                    .position(origin)
                    .opacity(progress > 0.05 ? 1 : 0)

                // Destination pin: red ring with white core.
                Circle()
                    .fill(Brand.red)
                    .frame(width: node * 1.05, height: node * 1.05)
                    .overlay(
                        Circle()
                            .fill(.white)
                            .frame(width: node * 0.44, height: node * 0.44)
                    )
                    .position(destination)
                    .scaleEffect(progress > 0.9 ? 1 : 0.2)
                    .opacity(progress > 0.85 ? 1 : 0)
            }
        }
    }

    private func point(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat) -> CGPoint {
        CGPoint(x: x * side, y: y * side)
    }
}

private struct RoutePath: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        return path
    }
}

#Preview {
    ZStack {
        Brand.backgroundGradient.ignoresSafeArea()
        BrandMark().frame(width: 200, height: 200)
    }
}
