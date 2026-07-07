import SwiftUI
import os

struct RoutePlannerView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var origin: NodeID?
    @State private var destination: NodeID?
    @State private var departure = Date.now
    @State private var profile = TravelProfile.fastest
    @State private var route: Route?
    @State private var errorMessage: String?
    @State private var isRouting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip") {
                    Picker("From", selection: $origin) {
                        Text("Select…").tag(nil as NodeID?)
                        ForEach(env.graph.namedNodes, id: \.id) { node in
                            Text(node.displayName ?? node.id.rawValue).tag(node.id as NodeID?)
                        }
                    }
                    Picker("To", selection: $destination) {
                        Text("Select…").tag(nil as NodeID?)
                        ForEach(env.graph.namedNodes, id: \.id) { node in
                            Text(node.displayName ?? node.id.rawValue).tag(node.id as NodeID?)
                        }
                    }
                    DatePicker("Departure", selection: $departure, displayedComponents: [.date, .hourAndMinute])
                    Picker("Profile", selection: $profile) {
                        ForEach(TravelProfile.presets) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                }

                Section {
                    Button(isRouting ? "Routing…" : "Find route") {
                        Task { await findRoute() }
                    }
                    .disabled(origin == nil || destination == nil || origin == destination || isRouting)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                if let route {
                    RouteResultSection(route: route)
                    Section {
                        Button("Start trip with Live Activity") {
                            Task { await startTrip(route) }
                        }
                        .disabled(env.tripSession.isActive)
                    }
                }

                if env.tripSession.isActive {
                    ActiveTripSection()
                }
            }
            .navigationTitle("NTUSync")
        }
    }

    private func findRoute() async {
        guard let origin, let destination else { return }
        isRouting = true
        defer { isRouting = false }
        errorMessage = nil
        do {
            route = try await env.routeEngine.route(
                RouteQuery(origin: origin, destination: destination, departure: departure, profile: profile)
            )
        } catch RoutingError.noRouteFound {
            route = nil
            errorMessage = "No route found for this profile — the shuttle may not be running at that time."
        } catch {
            route = nil
            errorMessage = "Routing failed: \(error)"
        }
    }

    private func startTrip(_ route: Route) async {
        let from = route.origin.map(env.displayName(for:)) ?? "?"
        let to = route.destination.map(env.displayName(for:)) ?? "?"
        try? await env.tripSession.start(route: route, summary: "\(from) → \(to)", nextClass: nil)
        env.location.setTier(.cruise)
        env.pedometer.start()
    }
}

struct RouteResultSection: View {
    @Environment(AppEnvironment.self) private var env
    let route: Route

    var body: some View {
        Section("Route · \(Int(route.totalSeconds / 60)) min · arrive \(route.arrivalTime.formatted(date: .omitted, time: .shortened))") {
            ForEach(route.legs) { leg in
                LegRow(leg: leg)
            }
            LabeledContent("Walking", value: "\(Int(route.totalWalkMetres)) m")
            LabeledContent("Rain-exposed", value: "\(Int(route.exposedMetres)) m")
        }
    }
}

struct LegRow: View {
    @Environment(AppEnvironment.self) private var env
    let leg: RouteLeg

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(leg.kind == .shuttle ? .red : .blue)
            VStack(alignment: .leading) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var icon: String {
        switch leg.kind {
        case .shuttle: "bus.fill"
        case .stairs: "figure.stairs"
        case .indoor: "building.2"
        case .shelteredWalk: "umbrella"
        case .walk: "figure.walk"
        }
    }

    private var title: String {
        if leg.kind == .shuttle, let line = leg.line {
            let stops = max(leg.nodes.count - 1, 1)
            return "\(line.rawValue) · \(stops) stop\(stops == 1 ? "" : "s")"
        }
        return "\(leg.kind == .walk ? "Walk" : leg.kind == .shelteredWalk ? "Sheltered walk" : leg.kind == .stairs ? "Stairs" : "Indoor") \(Int(leg.metres)) m"
    }

    private var subtitle: String {
        let from = leg.nodes.first.map(env.displayName(for:)) ?? ""
        let to = leg.nodes.last.map(env.displayName(for:)) ?? ""
        var text = "\(from) → \(to) · \(Int(leg.seconds / 60)) min"
        if let boarding = leg.boardingTime {
            text += " · board ~\(boarding.formatted(date: .omitted, time: .shortened))"
        }
        return text
    }
}

struct ActiveTripSection: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Section("Active trip · \(env.tripSession.phase?.rawValue ?? "")") {
            if let phase = env.tripSession.phase,
               let nexts = TripStateMachine.allowedTransitions[phase], !nexts.isEmpty {
                ForEach(Array(nexts).sorted { $0.rawValue < $1.rawValue }, id: \.self) { next in
                    Button("Advance: \(next.rawValue)") {
                        Task { try? await env.tripSession.advance(to: next) }
                    }
                }
            }
            Button("End trip", role: .destructive) {
                Task {
                    await env.tripSession.end()
                    env.pedometer.stop()
                    env.location.setTier(.idle)
                }
            }
        }
    }
}
