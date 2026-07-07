import SwiftUI
import SwiftData
import MapKit

struct BenchesView: View {
    @Query private var benches: [StudyBench]

    var body: some View {
        NavigationStack {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 1.3450, longitude: 103.6825),
                span: MKCoordinateSpan(latitudeDelta: 0.014, longitudeDelta: 0.014)
            ))) {
                ForEach(benches) { bench in
                    Marker(
                        bench.note ?? "Study bench",
                        systemImage: bench.hasPower ? "powerplug.fill" : "chair.lounge.fill",
                        coordinate: CLLocationCoordinate2D(latitude: bench.latitude, longitude: bench.longitude)
                    )
                    .tint(bench.isSheltered ? .green : .orange)
                }
            }
            .navigationTitle("Study benches")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Label("Sheltered", systemImage: "circle.fill").foregroundStyle(.green)
                    Label("Open-air", systemImage: "circle.fill").foregroundStyle(.orange)
                    Spacer()
                    Text("\(benches.count) benches")
                }
                .font(.caption)
                .padding(10)
                .background(.thinMaterial)
            }
        }
    }
}
