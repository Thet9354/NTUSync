import SwiftUI
import SwiftData
import MapKit
import PhotosUI

/// Street-level checkpoint imagery for a route leg: Apple Look Around where
/// covered (Singapore has full road coverage), a map snapshot as the offline
/// fallback, and a user-photo slot for indoor nodes Look Around can't see.
struct CheckpointSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let nodes: [NodeID]
    @State private var selected: NodeID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(nodes.enumerated()), id: \.element) { index, node in
                            FilterChip(
                                label: chipLabel(for: node, index: index),
                                icon: env.graph.nodes[node]?.isIndoor == true ? "building.2" : "mappin",
                                isOn: currentNode == node,
                                tint: Brand.navy
                            ) {
                                selected = node
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                if let node = currentNode, let graphNode = env.graph.nodes[node] {
                    CheckpointPreview(node: graphNode)
                        .id(node)   // restart scene lookup per checkpoint
                } else {
                    ContentUnavailableView("No checkpoints", systemImage: "mappin.slash")
                }
                Spacer(minLength: 0)
            }
            .navigationTitle("Checkpoints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var currentNode: NodeID? { selected ?? nodes.first }

    private func chipLabel(for node: NodeID, index: Int) -> String {
        env.graph.nodes[node]?.displayName ?? "Checkpoint \(index + 1)"
    }
}

struct CheckpointPreview: View {
    @Environment(\.modelContext) private var modelContext

    let node: GraphNode
    @Query private var photos: [CheckpointPhoto]
    @State private var scene: MKLookAroundScene?
    @State private var sceneLookupDone = false
    @State private var pickedItem: PhotosPickerItem?

    init(node: GraphNode) {
        self.node = node
        let nodeID = node.id.rawValue
        _photos = Query(filter: #Predicate<CheckpointPhoto> { $0.nodeID == nodeID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(node.displayName ?? node.id.rawValue)
                .font(.headline)
                .padding(.horizontal, 16)

            Group {
                if let data = photos.first?.photo, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let scene {
                    LookAroundPreview(initialScene: scene)
                } else if !sceneLookupDone {
                    ZStack {
                        mapFallback
                        ProgressView()
                    }
                } else {
                    mapFallback
                }
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)

            statusRow
                .padding(.horizontal, 16)
        }
        .task(id: node.id) {
            scene = nil
            sceneLookupDone = false
            // Indoor nodes have no street imagery by definition; skip the request.
            if !node.isIndoor {
                let request = MKLookAroundSceneRequest(coordinate: CLLocationCoordinate2D(
                    latitude: node.coordinate.latitude, longitude: node.coordinate.longitude
                ))
                scene = try? await request.scene
            }
            sceneLookupDone = true
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await attachPhoto(item) }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack {
            if photos.first != nil {
                Label("Your photo", systemImage: "photo.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Remove", role: .destructive) {
                    if let photo = photos.first {
                        modelContext.delete(photo)
                    }
                }
                .font(.caption)
            } else if scene != nil {
                Label("Apple Look Around · street-level imagery",
                      systemImage: "binoculars.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if sceneLookupDone {
                Label(node.isIndoor ? "Indoor checkpoint — no street imagery"
                                    : "Look Around unavailable (offline?) — showing map",
                      systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Label("Add photo", systemImage: "photo.badge.plus")
                        .font(.caption)
                }
            }
        }
    }

    private var mapFallback: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: node.coordinate.latitude,
                                           longitude: node.coordinate.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.0018, longitudeDelta: 0.0018)
        ))) {
            Marker(node.displayName ?? "Checkpoint", coordinate: CLLocationCoordinate2D(
                latitude: node.coordinate.latitude, longitude: node.coordinate.longitude
            ))
            .tint(Brand.red)
        }
        .allowsHitTesting(false)
    }

    private func attachPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = ImageProcessing.jpegForStorage(data) else { return }
        if let existing = photos.first {
            existing.photo = jpeg
        } else {
            modelContext.insert(CheckpointPhoto(nodeID: node.id.rawValue, photo: jpeg))
        }
        pickedItem = nil
    }
}
