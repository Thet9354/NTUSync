import SwiftUI
import SwiftData
import MapKit

struct BenchesView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var benches: [StudyBench]

    @State private var selectedBenchID: PersistentIdentifier?
    @State private var isPlacingBench = false
    @State private var pendingCoordinate: GeoPoint?
    /// Empty = every category visible; chips narrow the amenity layer.
    @State private var selectedCategories: Set<AmenityCategory> = []
    @State private var showAmenities = true

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 1.3465, longitude: 103.6840),
                    span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
                )), selection: $selectedBenchID) {
                    ForEach(benches) { bench in
                        Marker(
                            markerTitle(for: bench),
                            systemImage: bench.hasPower ? "powerplug.fill" : "chair.lounge.fill",
                            coordinate: CLLocationCoordinate2D(latitude: bench.latitude, longitude: bench.longitude)
                        )
                        .tint(bench.isSheltered ? .green : .orange)
                        .tag(bench.persistentModelID)
                    }
                    if showAmenities {
                        ForEach(env.amenities.amenities(in: selectedCategories)) { amenity in
                            Marker(
                                amenity.name,
                                systemImage: amenity.category.icon,
                                coordinate: CLLocationCoordinate2D(latitude: amenity.latitude, longitude: amenity.longitude)
                            )
                            .tint(amenity.category.tint)
                        }
                    }
                }
                .onTapGesture { screenPoint in
                    guard isPlacingBench,
                          let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                    pendingCoordinate = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    isPlacingBench = false
                }
            }
            .navigationTitle("Explore")
            .safeAreaInset(edge: .top) {
                categoryChips
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isPlacingBench ? "Cancel" : "Add bench",
                           systemImage: isPlacingBench ? "xmark" : "plus") {
                        isPlacingBench.toggle()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if isPlacingBench {
                        Label("Tap the map where the bench is", systemImage: "hand.tap")
                            .foregroundStyle(.blue)
                    } else {
                        Label("Sheltered", systemImage: "circle.fill").foregroundStyle(.green)
                        Label("Open-air", systemImage: "circle.fill").foregroundStyle(.orange)
                        Spacer()
                        Text("\(benches.count) benches")
                    }
                }
                .font(.caption)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
            }
            .sheet(item: selectedBenchBinding) { bench in
                BenchDetailView(bench: bench)
                    .presentationDetents([.medium])
            }
            .sheet(item: $pendingCoordinate) { coordinate in
                AddBenchView(coordinate: coordinate)
                    .presentationDetents([.medium])
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "Benches", icon: "chair.lounge.fill", isOn: true, tint: .green) {}
                FilterChip(label: "All places", icon: "sparkles", isOn: showAmenities && selectedCategories.isEmpty, tint: Brand.navy) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedCategories = []
                        showAmenities = true
                    }
                }
                ForEach(AmenityCategory.allCases, id: \.self) { category in
                    FilterChip(
                        label: category.displayName,
                        icon: category.icon,
                        isOn: showAmenities && selectedCategories.contains(category),
                        tint: category.tint
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showAmenities = true
                            if selectedCategories.contains(category) {
                                selectedCategories.remove(category)
                            } else {
                                selectedCategories.insert(category)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.thinMaterial)
    }

    private var selectedBenchBinding: Binding<StudyBench?> {
        Binding(
            get: { benches.first { $0.persistentModelID == selectedBenchID } },
            set: { selectedBenchID = $0?.persistentModelID }
        )
    }

    private func markerTitle(for bench: StudyBench) -> String {
        let stars = bench.userRating.map { String(repeating: "★", count: max(1, min(5, $0))) }
        return stars ?? bench.note ?? "Study bench"
    }
}

nonisolated extension GeoPoint: Identifiable {
    var id: String { "\(latitude),\(longitude)" }
}

extension AmenityCategory {
    var tint: Color {
        switch self {
        case .food: .orange
        case .supper: .indigo
        case .cafe: .brown
        case .supermarket: .green
        case .alcohol: .pink
        case .gym: .mint
        case .recreation: .cyan
        case .printing: .gray
        case .atm: .yellow
        case .clinic: Brand.red
        }
    }
}

struct FilterChip: View {
    let label: String
    let icon: String
    let isOn: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isOn ? tint : Color(.systemFill), in: Capsule())
                .foregroundStyle(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct AddBenchView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let coordinate: GeoPoint
    @State private var hasPower = false
    @State private var isSheltered = true
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("New bench") {
                    LabeledContent("Near", value: nearestNodeName)
                    Toggle("Power outlet", isOn: $hasPower)
                    Toggle("Sheltered", isOn: $isSheltered)
                    TextField("Note (e.g. \"quiet before 10am\")", text: $note)
                }
            }
            .navigationTitle("Add bench")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private var nearestNode: GraphNode? {
        env.graph.nearestNode(to: coordinate)
    }

    private var nearestNodeName: String {
        nearestNode.map { $0.displayName ?? $0.id.rawValue } ?? "—"
    }

    private func save() {
        modelContext.insert(StudyBench(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            graphNodeID: nearestNode?.id.rawValue ?? "",
            hasPower: hasPower,
            isSheltered: isSheltered,
            note: note.isEmpty ? nil : note
        ))
        dismiss()
    }
}

struct BenchDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var bench: StudyBench
    @State private var isRouting = false
    @State private var navigateError: String?
    @State private var showTripMap = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        Task { await navigate() }
                    } label: {
                        Label(isRouting ? "Routing…" : "Take me there",
                              systemImage: "figure.walk.circle.fill")
                            .font(.headline)
                    }
                    .disabled(isRouting || env.tripSession.isActive)
                    if let navigateError {
                        Label(navigateError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    LabeledContent("Near", value: nearName)
                    Toggle("Power outlet", isOn: $bench.hasPower)
                    Toggle("Sheltered", isOn: $bench.isSheltered)
                    TextField("Note", text: Binding(
                        get: { bench.note ?? "" },
                        set: { bench.note = $0.isEmpty ? nil : $0 }
                    ))
                }
                Section("Your rating") {
                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                // Tapping the current rating clears it.
                                bench.userRating = bench.userRating == star ? nil : star
                            } label: {
                                Image(systemName: star <= (bench.userRating ?? 0) ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(.yellow)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        if bench.userRating != nil {
                            Text("\(bench.userRating ?? 0)/5")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button("Delete bench", role: .destructive) {
                        modelContext.delete(bench)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Study bench")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showTripMap, onDismiss: { dismiss() }) {
                LiveTripView()
            }
        }
    }

    private func navigate() async {
        isRouting = true
        defer { isRouting = false }
        navigateError = nil

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
            navigateError = "No location fix yet — step outside or try again."
            return
        }
        do {
            let route = try await env.routeEngine.route(RouteQuery(
                origin: origin, destination: NodeID(bench.graphNodeID),
                departure: .now, profile: .fastest
            ))
            let to = bench.note ?? "study bench"
            try? await env.tripSession.start(
                route: route,
                summary: "\(env.displayName(for: origin)) → \(to)",
                nextClass: nil
            )
            env.beginTripSensing()
            showTripMap = true
        } catch {
            navigateError = "No route found from your position."
        }
    }

    private var nearName: String {
        let node = env.graph.nodes[NodeID(bench.graphNodeID)]
        return node?.displayName ?? bench.graphNodeID
    }
}
