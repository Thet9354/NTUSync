import SwiftUI
import MapKit

/// Full-screen live trip: route on the map, real-time user position, progress,
/// and phase controls. The in-app counterpart of the Live Activity.
struct LiveTripView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var camera: MapCameraPosition = .automatic
    @State private var showingCompass = false

    var body: some View {
        ZStack(alignment: .top) {
            if showingCompass {
                CompassModeView()
            } else {
                tripMap
            }
            headerCard
        }
        .safeAreaInset(edge: .bottom) { controls }
        .onChange(of: env.tripSession.isActive) { _, active in
            if !active { dismiss() }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: env.tripSession.phase)
    }

    private var tripMap: some View {
        Map(position: $camera) {
            if let route = env.tripSession.route {
                let geometry = RouteMapGeometry(route: route, graph: env.graph)
                ForEach(Array(geometry.segments.enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(segment.kind.mapColor, style: StrokeStyle(
                            lineWidth: 6, lineCap: .round, lineJoin: .round,
                            dash: segment.kind == .shuttle ? [] : [1, 8]
                        ))
                }
                if let destination = geometry.destination {
                    Marker(route.destination.map(env.displayName(for:)) ?? "Destination",
                           systemImage: "flag.checkered", coordinate: destination)
                    .tint(Brand.red)
                }
            }
            UserAnnotation()
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var headerCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: phaseIcon)
                    .font(.title2)
                    .foregroundStyle(Brand.red)
                    .symbolEffect(.pulse, isActive: isLivePhase)
                VStack(alignment: .leading, spacing: 2) {
                    Text(phaseHeadline)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                countdown
                Button {
                    withAnimation { showingCompass.toggle() }
                } label: {
                    Image(systemName: showingCompass ? "map.fill" : "location.north.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Brand.navy)
                }
                .accessibilityLabel(showingCompass ? "Show map" : "Show compass")
            }
            if let progress = env.tripSession.progressFraction {
                ProgressView(value: progress)
                    .tint(env.tripSession.isDeadReckoning ? .orange : Brand.red)
                if env.tripSession.isDeadReckoning {
                    Label("Position approximate — tracking steps indoors", systemImage: "location.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    @ViewBuilder
    private var countdown: some View {
        let shuttleLeg = env.tripSession.route?.legs.first { $0.kind == .shuttle }
        if let boarding = shuttleLeg?.boardingTime,
           boarding > .now,
           env.tripSession.phase == .walkingToStop || env.tripSession.phase == .waitingForBus {
            VStack(alignment: .trailing, spacing: 0) {
                Text(timerInterval: Date.now...boarding, countsDown: true)
                    .font(.title3.monospacedDigit().weight(.semibold))
                Text("to bus")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if let arrival = env.tripSession.route?.arrivalTime {
            VStack(alignment: .trailing, spacing: 0) {
                Text(arrival.formatted(date: .omitted, time: .shortened))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
                Text("arrival")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if let phase = env.tripSession.phase,
               let next = TripStateMachine.allowedTransitions[phase]?.sorted(by: { $0.rawValue < $1.rawValue }).first {
                Button {
                    Task { try? await env.tripSession.advance(to: next) }
                } label: {
                    Label(advanceLabel(for: next), systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.navy)
            }
            Button(role: .destructive) {
                Task {
                    await env.tripSession.end()
                    env.endTripSensing()
                }
            } label: {
                Label("End", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var isLivePhase: Bool {
        env.tripSession.phase == .waitingForBus || env.tripSession.phase == .riding
    }

    private var phaseIcon: String {
        switch env.tripSession.phase {
        case .walkingToStop, .walkingToClass: "figure.walk"
        case .waitingForBus: "clock.badge"
        case .riding: "bus.fill"
        case .arrived: "checkmark.circle.fill"
        case nil: "map"
        }
    }

    private var phaseHeadline: String {
        switch env.tripSession.phase {
        case .walkingToStop: "Walk to the stop"
        case .waitingForBus: "Waiting for the bus"
        case .riding: "On the shuttle"
        case .walkingToClass: "Almost there"
        case .arrived: "Arrived"
        case nil: "No active trip"
        }
    }

    private var subtitle: String {
        guard let route = env.tripSession.route else { return "" }
        let to = route.destination.map(env.displayName(for:)) ?? "?"
        return "To \(to) · \(Int(route.totalWalkMetres)) m on foot"
    }

    private func advanceLabel(for phase: TripPhase) -> String {
        switch phase {
        case .walkingToStop: "Walking to stop"
        case .waitingForBus: "At the stop"
        case .riding: "On board"
        case .walkingToClass: "Off the bus"
        case .arrived: "I've arrived"
        }
    }
}
