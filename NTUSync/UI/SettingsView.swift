import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [UserSettings]

    var body: some View {
        NavigationStack {
            Form {
                if let userSettings = settings.first {
                    Section {
                        DatePicker(
                            "Week 1 Monday",
                            selection: Binding(
                                get: { userSettings.semesterStartDate },
                                set: { userSettings.semesterStartDate = Calendar.current.startOfDay(for: $0) }
                            ),
                            displayedComponents: .date
                        )
                    } header: {
                        Text("Semester")
                    } footer: {
                        Text("Set this to the Monday of teaching week 1. Next-class times and odd/even-week sessions are computed from this anchor, with recess after week 7.")
                    }
                } else {
                    Section("Semester") {
                        Text("Settings are created on first launch — restart the app.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Campus data") {
                    LabeledContent("Graph nodes", value: "\(env.graph.nodes.count)")
                    LabeledContent("Graph edges", value: "\(env.graph.edgeCount)")
                    LabeledContent("Shuttle lines", value: "\(env.timetable.lines.count)")
                    LabeledContent("Timetable valid until", value: env.timetable.validUntil)
                    if let seedVersion = settings.first?.seedVersion {
                        LabeledContent("Seed version", value: "\(seedVersion)")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    Text("All routing and schedule data lives on-device. NTUSync makes no network requests.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
