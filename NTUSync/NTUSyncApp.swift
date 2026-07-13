import SwiftUI
import SwiftData
import os

@main
struct NTUSyncApp: App {
    @State private var env = AppEnvironment()
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .task {
                    await Self.seed(container: container)
                }
        }
        .modelContainer(container)
    }

    /// §5.5 recovery: a store that fails to open is moved aside and rebuilt
    /// from seed rather than bricking the app.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, migrationPlan: NTUSyncMigrationPlan.self, configurations: [configuration])
        } catch {
            Logger.persistence.fault("store unopenable, moving aside: \(String(describing: error))")
            let storeURL = configuration.url
            let corruptURL = storeURL.deletingLastPathComponent()
                .appendingPathComponent("\(storeURL.lastPathComponent).corrupt-\(Int(Date.now.timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: storeURL, to: corruptURL)
            do {
                return try ModelContainer(for: schema, migrationPlan: NTUSyncMigrationPlan.self, configurations: [configuration])
            } catch {
                fatalError("SwiftData store unrecoverable: \(error)")
            }
        }
    }

    private static func seed(container: ModelContainer) async {
        let store = PersistenceStore(modelContainer: container)
        do {
            try await store.seedIfNeeded()
        } catch {
            Logger.persistence.error("seeding failed: \(String(describing: error))")
        }
    }
}
