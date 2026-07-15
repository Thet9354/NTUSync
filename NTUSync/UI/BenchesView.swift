import SwiftUI
import SwiftData
import MapKit
import TipKit

struct BenchesView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var benches: [StudyBench]
    @Query private var userPlaces: [UserPlace]

    /// Anything tappable on the map: user benches, curated amenity pins, and
    /// user-pinned places.
    enum MapPick: Hashable {
        case bench(PersistentIdentifier)
        case amenity(String)
        case place(PersistentIdentifier)
    }

    private static let campusRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 1.3465, longitude: 103.6840),
        span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
    )

    @State private var selection: MapPick?
    @State private var searchedNode: NodeID?
    @State private var isPlacingPin = false
    @State private var pendingCoordinate: GeoPoint?
    /// Empty = every category visible; chips narrow the amenity layer.
    @State private var selectedCategories: Set<AmenityCategory> = []
    @State private var showAmenities = true

    @State private var camera: MapCameraPosition = .region(Self.campusRegion)
    @State private var lastCamera: MapCamera?
    @State private var is3D = false
    @State private var isSatellite = false
    @State private var searchQuery = ""

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $camera, selection: $selection) {
                    ForEach(benches) { bench in
                        Marker(
                            markerTitle(for: bench),
                            systemImage: bench.hasPower ? "powerplug.fill" : "chair.lounge.fill",
                            coordinate: CLLocationCoordinate2D(latitude: bench.latitude, longitude: bench.longitude)
                        )
                        .tint(bench.isSheltered ? .green : .orange)
                        .tag(MapPick.bench(bench.persistentModelID))
                    }
                    ForEach(visiblePlaces) { place in
                        Marker(
                            place.name,
                            systemImage: place.icon,
                            coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
                        )
                        .tint(place.category?.tint ?? .purple)
                        .tag(MapPick.place(place.persistentModelID))
                    }
                    if showAmenities {
                        ForEach(env.amenities.amenities(in: selectedCategories)) { amenity in
                            Marker(
                                amenity.name,
                                systemImage: amenity.category.icon,
                                coordinate: CLLocationCoordinate2D(latitude: amenity.latitude, longitude: amenity.longitude)
                            )
                            .tint(amenity.category.tint)
                            .tag(MapPick.amenity(amenity.id))
                        }
                    }
                }
                .mapStyle(isSatellite ? .hybrid(elevation: .realistic)
                                      : .standard(elevation: .realistic))
                .onMapCameraChange { context in
                    lastCamera = context.camera
                }
                .onTapGesture { screenPoint in
                    guard isPlacingPin,
                          let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                    pendingCoordinate = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    isPlacingPin = false
                }
            }
            .overlay(alignment: .topTrailing) {
                mapModeButtons
            }
            .overlay {
                if !trimmedQuery.isEmpty {
                    searchResults
                }
            }
            .navigationTitle("Explore")
            .searchable(text: $searchQuery, prompt: "Search NTU campus")
            .safeAreaInset(edge: .top) {
                categoryChips
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isPlacingPin ? "Cancel" : "Add pin",
                           systemImage: isPlacingPin ? "xmark" : "plus") {
                        isPlacingPin.toggle()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if !isPlacingPin {
                        HallShelf()
                    }
                    HStack {
                        if isPlacingPin {
                            Label("Tap the map where it is", systemImage: "hand.tap")
                                .foregroundStyle(.blue)
                        } else {
                            Label("Sheltered", systemImage: "circle.fill").foregroundStyle(.green)
                            Label("Open-air", systemImage: "circle.fill").foregroundStyle(.orange)
                            Spacer()
                            Text("\(benches.count) benches · \(userPlaces.count) pins")
                        }
                    }
                    .font(.caption)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
                }
            }
            .sheet(item: selectedBenchBinding) { bench in
                BenchDetailView(bench: bench)
                    .presentationDetents([.medium])
            }
            .sheet(item: selectedAmenityBinding) { amenity in
                AmenityDetailView(amenity: amenity)
                    .presentationDetents([.medium])
            }
            .sheet(item: selectedPlaceBinding) { place in
                PlaceDetailView(place: place)
                    .presentationDetents([.medium])
            }
            .sheet(item: $searchedNode) { nodeID in
                NodeDetailView(nodeID: nodeID)
                    .presentationDetents([.medium])
            }
            .sheet(item: $pendingCoordinate) { coordinate in
                AddPinView(coordinate: coordinate)
                    .presentationDetents([.large])
            }
        }
    }

    // MARK: Map mode controls

    /// Apple-Maps-style stacked controls: 2D/3D pitch and standard/satellite.
    private var mapModeButtons: some View {
        VStack(spacing: 10) {
            Button {
                toggle3D()
            } label: {
                Text(is3D ? "2D" : "3D")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel(is3D ? "Switch to 2D map" : "Switch to 3D map")
            Button {
                isSatellite.toggle()
            } label: {
                Image(systemName: isSatellite ? "map.fill" : "globe.asia.australia.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel(isSatellite ? "Switch to standard map" : "Switch to satellite map")
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
        .padding(.trailing, 12)
    }

    /// Re-pitch the camera in place; everything else about the view carries over.
    private func toggle3D() {
        is3D.toggle()
        guard let cam = lastCamera else { return }
        withAnimation(.easeInOut(duration: 0.6)) {
            camera = .camera(MapCamera(
                centerCoordinate: cam.centerCoordinate,
                distance: cam.distance,
                heading: cam.heading,
                pitch: is3D ? 60 : 0
            ))
        }
    }

    // MARK: Search (campus dataset only — offline, never MKLocalSearch)

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchResults: some View {
        let results = ExploreSearch.matches(query: trimmedQuery, in: searchCandidates)
        return List {
            if results.isEmpty {
                ContentUnavailableView.search(text: trimmedQuery)
            }
            ForEach(results) { result in
                Button {
                    open(result)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: result.icon)
                            .foregroundStyle(Brand.navy)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                            if let subtitle = result.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.visible)
    }

    /// Everything findable: named graph nodes, curated amenities, benches,
    /// and user pins. Keys carry the kind so `open` can route the selection.
    private var searchCandidates: [SearchCandidate] {
        var out: [SearchCandidate] = env.graph.namedNodes.map { node in
            SearchCandidate(
                key: "node:\(node.id.rawValue)",
                title: node.displayName ?? node.id.rawValue,
                subtitle: "Campus location",
                icon: "building.2",
                latitude: node.coordinate.latitude, longitude: node.coordinate.longitude
            )
        }
        out += env.amenities.amenities.map { amenity in
            SearchCandidate(
                key: "amenity:\(amenity.id)",
                title: amenity.name,
                subtitle: amenity.category.displayName,
                icon: amenity.category.icon,
                latitude: amenity.latitude, longitude: amenity.longitude
            )
        }
        out += benches.enumerated().map { index, bench in
            SearchCandidate(
                key: "bench:\(index)",
                title: bench.note ?? "Study bench",
                subtitle: "Study bench",
                icon: "chair.lounge.fill",
                latitude: bench.latitude, longitude: bench.longitude
            )
        }
        out += userPlaces.enumerated().map { index, place in
            SearchCandidate(
                key: "place:\(index)",
                title: place.name,
                subtitle: place.category?.displayName ?? "My pin",
                icon: place.icon,
                latitude: place.latitude, longitude: place.longitude
            )
        }
        return out
    }

    /// Jump the camera to the result and open its detail sheet.
    private func open(_ result: SearchCandidate) {
        searchQuery = ""
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: result.latitude, longitude: result.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
        }
        let parts = result.key.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return }
        let id = String(parts[1])
        switch parts[0] {
        case "node":
            searchedNode = NodeID(id)
        case "amenity":
            selection = .amenity(id)
        case "bench":
            if let index = Int(id), benches.indices.contains(index) {
                selection = .bench(benches[index].persistentModelID)
            }
        case "place":
            if let index = Int(id), userPlaces.indices.contains(index) {
                selection = .place(userPlaces[index].persistentModelID)
            }
        default:
            break
        }
    }

    // MARK: Chips / bindings

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "Benches", icon: "chair.lounge.fill", isOn: true, tint: .green) {}
                FilterChip(label: "All places", icon: "square.grid.2x2", isOn: showAmenities && selectedCategories.isEmpty, tint: Brand.navy) {
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
        .popoverTip(ExploreTip())
    }

    /// User pins follow the category filter; custom (uncategorised) pins show
    /// whenever no filter is active.
    private var visiblePlaces: [UserPlace] {
        userPlaces.filter { place in
            selectedCategories.isEmpty || place.category.map(selectedCategories.contains) == true
        }
    }

    private var selectedBenchBinding: Binding<StudyBench?> {
        Binding(
            get: {
                guard case .bench(let id) = selection else { return nil }
                return benches.first { $0.persistentModelID == id }
            },
            set: { selection = $0.map { .bench($0.persistentModelID) } }
        )
    }

    private var selectedAmenityBinding: Binding<Amenity?> {
        Binding(
            get: {
                guard case .amenity(let id) = selection else { return nil }
                return env.amenities.amenities.first { $0.id == id }
            },
            set: { selection = $0.map { .amenity($0.id) } }
        )
    }

    private var selectedPlaceBinding: Binding<UserPlace?> {
        Binding(
            get: {
                guard case .place(let id) = selection else { return nil }
                return userPlaces.first { $0.persistentModelID == id }
            },
            set: { selection = $0.map { .place($0.persistentModelID) } }
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

nonisolated extension NodeID: Identifiable {
    var id: String { rawValue }
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

// MARK: - Shared "Take me there"

/// One implementation of the GPS-fix → nearest-node → route → live-trip flow
/// every detail sheet uses. Returns an error message, or nil once the trip
/// has started.
@MainActor
func startTakeMeThereTrip(to destination: NodeID, named name: String,
                          env: AppEnvironment) async -> String? {
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
        return "No location fix yet — step outside or try again."
    }
    do {
        let route = try await env.routeEngine.route(RouteQuery(
            origin: origin, destination: destination,
            departure: .now, profile: .fastest
        ))
        try? await env.tripSession.start(
            route: route,
            summary: "\(env.displayName(for: origin)) → \(name)",
            nextClass: nil
        )
        env.beginTripSensing()
        return nil
    } catch {
        return "No route found from your position."
    }
}

// MARK: - Add pin

/// Add flow for a tapped map point: a study bench (the original flow) or any
/// other kind of place — food, supper, café, … or a fully custom pin.
struct AddPinView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum PinKind: String, CaseIterable {
        case bench = "Study bench"
        case place = "Place"
    }

    let coordinate: GeoPoint
    @State private var kind: PinKind = .bench

    // Bench fields
    @State private var hasPower = false
    @State private var isSheltered = true
    @State private var benchNote = ""
    @State private var photo: Data?

    // Place fields
    @State private var name = ""
    @State private var category: AmenityCategory? = .food
    @State private var placeNote = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Pin type", selection: $kind) {
                        ForEach(PinKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Near", value: nearestNodeName)
                }
                switch kind {
                case .bench:
                    Section("Study bench") {
                        Toggle("Power outlet", isOn: $hasPower)
                        Toggle("Sheltered", isOn: $isSheltered)
                        TextField("Note (e.g. \"quiet before 10am\")", text: $benchNote)
                    }
                    BenchPhotoSection(photoData: $photo)
                case .place:
                    Section("Place") {
                        TextField("Name (e.g. \"Mala stall\")", text: $name)
                        Picker("Category", selection: $category) {
                            ForEach(AmenityCategory.allCases, id: \.self) { category in
                                Label(category.displayName, systemImage: category.icon)
                                    .tag(category as AmenityCategory?)
                            }
                            Label("Custom pin", systemImage: "mappin")
                                .tag(nil as AmenityCategory?)
                        }
                        TextField("Note", text: $placeNote)
                    }
                }
            }
            .navigationTitle("Add pin")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(kind == .place && name.trimmingCharacters(in: .whitespaces).isEmpty)
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
        switch kind {
        case .bench:
            modelContext.insert(StudyBench(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                graphNodeID: nearestNode?.id.rawValue ?? "",
                hasPower: hasPower,
                isSheltered: isSheltered,
                note: benchNote.isEmpty ? nil : benchNote,
                photo: photo
            ))
        case .place:
            modelContext.insert(UserPlace(
                name: name.trimmingCharacters(in: .whitespaces),
                categoryRaw: category?.rawValue,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                graphNodeID: nearestNode?.id.rawValue ?? "",
                note: placeNote.isEmpty ? nil : placeNote
            ))
        }
        dismiss()
    }
}

// MARK: - Detail sheets

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
                BenchPhotoSection(photoData: $bench.photo)
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
        navigateError = await startTakeMeThereTrip(
            to: NodeID(bench.graphNodeID), named: bench.note ?? "study bench", env: env)
        if navigateError == nil { showTripMap = true }
    }

    private var nearName: String {
        let node = env.graph.nodes[NodeID(bench.graphNodeID)]
        return node?.displayName ?? bench.graphNodeID
    }
}

/// Detail sheet for a curated amenity pin — read-only info plus the same
/// "Take me there" trip flow benches get.
struct AmenityDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let amenity: Amenity
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
                    LabeledContent("Category") {
                        Label(amenity.category.displayName, systemImage: amenity.category.icon)
                            .foregroundStyle(amenity.category.tint)
                    }
                    LabeledContent("Near", value: nearName)
                    LabeledContent("Hours") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(amenity.isOpen(at: .now) ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text("\(amenity.isOpen(at: .now) ? "Open" : "Closed") · \(amenity.hoursText)")
                        }
                    }
                    if let note = amenity.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(amenity.name)
            .navigationBarTitleDisplayMode(.inline)
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
        navigateError = await startTakeMeThereTrip(
            to: amenity.graphNodeID, named: amenity.name, env: env)
        if navigateError == nil { showTripMap = true }
    }

    private var nearName: String {
        env.graph.nodes[amenity.graphNodeID]?.displayName ?? amenity.graphNodeID.rawValue
    }
}

/// Detail sheet for a user-pinned place: editable note, category, take-me-there,
/// delete.
struct PlaceDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var place: UserPlace
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
                    LabeledContent("Category") {
                        Label(place.category?.displayName ?? "Custom pin", systemImage: place.icon)
                            .foregroundStyle(place.category?.tint ?? .purple)
                    }
                    LabeledContent("Near", value: nearName)
                    TextField("Note", text: Binding(
                        get: { place.note ?? "" },
                        set: { place.note = $0.isEmpty ? nil : $0 }
                    ))
                }
                Section {
                    Button("Delete pin", role: .destructive) {
                        modelContext.delete(place)
                        dismiss()
                    }
                }
            }
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
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
        navigateError = await startTakeMeThereTrip(
            to: NodeID(place.graphNodeID), named: place.name, env: env)
        if navigateError == nil { showTripMap = true }
    }

    private var nearName: String {
        env.graph.nodes[NodeID(place.graphNodeID)]?.displayName ?? place.graphNodeID
    }
}

/// Minimal sheet for a campus building found via search: name + take-me-there.
struct NodeDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let nodeID: NodeID
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
                if let node = env.graph.nodes[nodeID] {
                    Section {
                        LabeledContent("Type", value: node.isIndoor ? "Indoor location" : "Outdoor location")
                    }
                }
            }
            .navigationTitle(env.displayName(for: nodeID))
            .navigationBarTitleDisplayMode(.inline)
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
        navigateError = await startTakeMeThereTrip(
            to: nodeID, named: env.displayName(for: nodeID), env: env)
        if navigateError == nil { showTripMap = true }
    }
}
