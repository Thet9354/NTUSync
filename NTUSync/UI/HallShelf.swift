import SwiftUI
import SwiftData

/// Personal "from your hall" shelf on the Explore tab: nearest open food,
/// groceries, gym, and study spot ranked by real walk time from the user's
/// hall, plus one-tap "route home" from wherever the user currently is.
struct HallShelf: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var settings: [UserSettings]
    @Query private var benches: [StudyBench]

    @State private var items: [HallShelfItem] = []
    @State private var isRoutingHome = false
    @State private var routeError: String?
    @State private var showTripMap = false

    private var homeNodeID: String? { settings.first?.homeNodeID }

    var body: some View {
        if let homeNodeID {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("From \(env.displayName(for: NodeID(homeNodeID)))",
                          systemImage: "house.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await routeHome() }
                    } label: {
                        Label(isRoutingHome ? "Routing…" : "Route home",
                              systemImage: "house.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .tint(Brand.navy)
                    .disabled(isRoutingHome || env.tripSession.isActive)
                }
                .padding(.horizontal, 12)

                if let routeError {
                    Text(routeError)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            HallShelfCard(item: item) {
                                Task { await navigate(to: item.destination, named: item.title) }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 8)
            .background(.thinMaterial)
            .task(id: ShelfInput(home: homeNodeID, benchCount: benches.count)) {
                await refreshShelf(home: homeNodeID)
            }
            .fullScreenCover(isPresented: $showTripMap) {
                LiveTripView()
            }
        }
    }

    private struct ShelfInput: Equatable {
        let home: String
        let benchCount: Int
    }

    private func refreshShelf(home: String) async {
        let candidates = benches.map {
            BenchCandidate(graphNodeID: NodeID($0.graphNodeID),
                           hasPower: $0.hasPower,
                           isSheltered: $0.isSheltered,
                           note: $0.note)
        }
        items = await HallShelfPlanner.shelf(
            from: NodeID(home), at: .now,
            benches: candidates, amenities: env.amenities,
            graph: env.graph, engine: env.routeEngine
        )
    }

    private func routeHome() async {
        guard let homeNodeID else { return }
        isRoutingHome = true
        defer { isRoutingHome = false }
        await navigate(to: NodeID(homeNodeID), named: "home")
    }

    /// Current GPS fix → nearest node → trip with Live Activity.
    private func navigate(to destination: NodeID, named title: String) async {
        routeError = nil
        env.location.requestPermission()
        env.location.startUpdates()
        var origin: NodeID?
        for _ in 0..<6 {
            if let fix = env.location.lastFix {
                origin = await env.routeEngine.nearestNode(to: fix, where: { !$0.isIndoor })
                break
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard let origin else {
            routeError = "No location fix yet — step outside or try again."
            return
        }
        guard origin != destination else {
            routeError = "You're already there."
            return
        }
        do {
            let route = try await env.routeEngine.route(RouteQuery(
                origin: origin, destination: destination,
                departure: .now, profile: .fastest
            ))
            try? await env.tripSession.start(
                route: route,
                summary: "\(env.displayName(for: origin)) → \(title)",
                nextClass: nil
            )
            env.beginTripSensing()
            showTripMap = true
        } catch {
            routeError = "No route found from your position."
        }
    }
}

private struct HallShelfCard: View {
    let item: HallShelfItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.body)
                    .foregroundStyle(item.category?.tint ?? .green)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.slot.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(item.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
