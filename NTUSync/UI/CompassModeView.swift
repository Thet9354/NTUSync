import SwiftUI

/// Compass mode: a big arrow that rotates toward the next route checkpoint
/// using device heading — the offline answer to "which way do I even walk?"
/// when emerging from a basement disoriented. All math is in `CompassMath`;
/// this view just binds sensors to geometry.
struct CompassModeView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            dial
            statusText
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task {
            env.location.startHeadingUpdates()
        }
        .onDisappear {
            env.location.stopHeadingUpdates()
        }
    }

    /// Next checkpoint from the current fix, snapped along the active route.
    private var target: CompassTarget? {
        guard let route = env.tripSession.route, let fix = env.location.lastFix else { return nil }
        return CompassMath.nextCheckpoint(legs: route.legs, position: fix) {
            env.graph.nodes[$0]?.coordinate
        }
    }

    private var rotation: Double? {
        guard let target, let heading = env.location.headingDegrees else { return nil }
        return CompassMath.relativeAngle(bearing: target.bearingDegrees, heading: heading)
    }

    private var dial: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
            Image(systemName: "location.north.fill")
                .font(.system(size: 96, weight: .bold))
                .foregroundStyle(rotation == nil ? AnyShapeStyle(.tertiary)
                                                 : AnyShapeStyle(Brand.navy))
                .rotationEffect(.degrees(rotation ?? 0))
                .animation(.spring(duration: 0.35), value: rotation)
                .accessibilityLabel(accessibilityDirection)
        }
        .frame(width: 240, height: 240)
    }

    @ViewBuilder
    private var statusText: some View {
        if let target {
            VStack(spacing: 6) {
                Text(env.displayName(for: target.nodeID))
                    .font(.title2.weight(.bold))
                HStack(spacing: 6) {
                    Text(CompassMath.distanceText(metres: target.distanceMetres))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText())
                    if let rotation {
                        Text(CompassMath.arrowGlyph(relativeAngle: rotation))
                            .font(.title3.weight(.semibold))
                    }
                }
                .foregroundStyle(.secondary)
                if env.location.headingDegrees == nil {
                    Label("Compass warming up — move outdoors and hold the phone flat",
                          systemImage: "location.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !CompassMath.isHeadingReliable(accuracyDegrees: env.location.headingAccuracy) {
                    Label("Heading approximate — step away from metal and re-orient",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        } else {
            Label(env.tripSession.route == nil ? "No active route" : "Waiting for a GPS fix…",
                  systemImage: "location.magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityDirection: String {
        guard let rotation else { return "Direction unavailable" }
        switch CompassMath.arrowGlyph(relativeAngle: rotation) {
        case "↑": return "Straight ahead"
        case "↗": return "Ahead and to the right"
        case "→": return "To the right"
        case "↘": return "Behind and to the right"
        case "↓": return "Behind you"
        case "↙": return "Behind and to the left"
        case "←": return "To the left"
        default: return "Ahead and to the left"
        }
    }
}
