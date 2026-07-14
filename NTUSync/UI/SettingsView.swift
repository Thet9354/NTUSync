import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [UserSettings]
    @Query(sort: \Course.code) private var courses: [Course]
    @State private var isExporting = false
    @State private var exportStatus: String?
    @State private var icsURL: URL?

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

                if let userSettings = settings.first {
                    Section {
                        Picker("My hall", selection: Binding(
                            get: { userSettings.homeNodeID },
                            set: { userSettings.homeNodeID = $0 }
                        )) {
                            Text("Not set").tag(nil as String?)
                            ForEach(hallNodes, id: \.id) { node in
                                Text(node.displayName ?? node.id.rawValue)
                                    .tag(node.id.rawValue as String?)
                            }
                        }
                        Toggle("Leave-now alerts", isOn: Binding(
                            get: { userSettings.leaveAlertsEnabled },
                            set: { userSettings.leaveAlertsEnabled = $0 }
                        ))
                        .disabled(userSettings.homeNodeID == nil)
                        if userSettings.leaveAlertsEnabled {
                            Stepper(
                                "Buffer: \(userSettings.leaveBufferMinutes) min",
                                value: Binding(
                                    get: { userSettings.leaveBufferMinutes },
                                    set: { userSettings.leaveBufferMinutes = $0 }
                                ),
                                in: 0...30, step: 5
                            )
                        }
                    } header: {
                        Text("My hall")
                    } footer: {
                        Text(userSettings.homeNodeID == nil
                             ? "Pick your hall to unlock the home shelf and \"leave now\" alerts timed by real route durations."
                             : "You'll be notified at class start − route time − buffer, with the route computed from \(hallName(userSettings.homeNodeID)) by the offline engine.")
                    }
                    .onChange(of: userSettings.homeNodeID) { rescheduleAlerts() }
                    .onChange(of: userSettings.leaveAlertsEnabled) { rescheduleAlerts() }
                    .onChange(of: userSettings.leaveBufferMinutes) { rescheduleAlerts() }
                }

                Section {
                    Button {
                        Task { await exportToCalendar() }
                    } label: {
                        Label(isExporting ? "Exporting…" : "Export timetable to Calendar",
                              systemImage: "calendar.badge.plus")
                    }
                    .disabled(isExporting || courses.isEmpty || settings.first == nil)
                    if let exportStatus {
                        Text(exportStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Calendar")
                } footer: {
                    Text("Writes every session of the semester as individual dated events into a dedicated \"NTUSync\" calendar — odd/even weeks and the recess week stay correct. Re-exporting replaces the previous export. Google Calendar works too if your Google account is added to iOS Calendar.")
                }

                Section {
                    if let icsURL {
                        ShareLink(item: icsURL) {
                            Label("Share semester as .ics file", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Label("Add courses to share a .ics file", systemImage: "square.and.arrow.up")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Any calendar app")
                } footer: {
                    Text("Exports the whole semester as a standard .ics file — one dated event per session — that opens in Google Calendar, Outlook, or any calendar app. It's just a file, so no permissions are needed.")
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
            .task(id: icsSignature) { rebuildICS() }
        }
    }

    /// Changes whenever the exported schedule would change, so the shared `.ics`
    /// file is regenerated to match the current courses.
    private var icsSignature: Int {
        var hasher = Hasher()
        hasher.combine(settings.first?.semesterStartDate)
        for course in courses {
            hasher.combine(course.code)
            for session in course.sessions {
                hasher.combine(session.kind)
                hasher.combine(session.dayOfWeek)
                hasher.combine(session.startMinutes)
                hasher.combine(session.durationMinutes)
                hasher.combine(session.teachingWeeksMask)
                hasher.combine(session.venue?.shortName)
            }
        }
        return hasher.finalize()
    }

    /// Write the semester `.ics` to a temp file for `ShareLink`; clears the link
    /// when there's nothing to export.
    private func rebuildICS() {
        guard let semesterStart = settings.first?.semesterStartDate, !courses.isEmpty else {
            icsURL = nil
            return
        }
        let snapshots = SessionSnapshot.snapshots(of: courses)
        let events = TimetableEventPlanner.events(for: snapshots, semesterStart: semesterStart)
        guard !events.isEmpty else {
            icsURL = nil
            return
        }
        let ics = ICSExporter.makeCalendar(from: events)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NTUSync-Semester.ics")
        do {
            try ics.write(to: url, atomically: true, encoding: .utf8)
            icsURL = url
        } catch {
            icsURL = nil
        }
    }

    /// Residential nodes: `hall.*` plus the named hall buildings, minus bus stops.
    private var hallNodes: [GraphNode] {
        env.graph.namedNodes.filter { node in
            !node.id.rawValue.hasPrefix("stop.")
                && (node.id.rawValue.hasPrefix("hall.")
                    || node.displayName?.localizedCaseInsensitiveContains("hall") == true)
        }
    }

    private func hallName(_ nodeID: String?) -> String {
        nodeID.flatMap { env.graph.nodes[NodeID($0)]?.displayName } ?? "your hall"
    }

    private func rescheduleAlerts() {
        guard let userSettings = settings.first else { return }
        let sessions = SessionSnapshot.snapshots(of: courses)
        let semesterStart = userSettings.semesterStartDate
        let home = userSettings.homeNodeID
        let buffer = userSettings.leaveBufferMinutes
        let enabled = userSettings.leaveAlertsEnabled
        Task {
            await env.leaveAlerts.reschedule(
                sessions: sessions, semesterStart: semesterStart,
                homeNodeID: home, bufferMinutes: buffer,
                enabled: enabled, engine: env.routeEngine
            )
        }
    }

    private func exportToCalendar() async {
        guard let semesterStart = settings.first?.semesterStartDate else { return }
        isExporting = true
        defer { isExporting = false }
        exportStatus = nil

        let snapshots = SessionSnapshot.snapshots(of: courses)
        let events = TimetableEventPlanner.events(for: snapshots, semesterStart: semesterStart)
        do {
            let count = try await CalendarExporter().export(events)
            exportStatus = "Exported \(count) events to the NTUSync calendar."
        } catch CalendarExportError.accessDenied {
            exportStatus = "Calendar access declined — allow it in Settings › Privacy › Calendars."
        } catch CalendarExportError.nothingToExport {
            exportStatus = "Nothing to export — add sessions to your courses first."
        } catch {
            exportStatus = "Export failed: \(error.localizedDescription)"
        }
    }
}
