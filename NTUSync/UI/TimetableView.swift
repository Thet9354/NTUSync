import SwiftUI
import SwiftData

struct TimetableView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.code) private var courses: [Course]
    @Query private var settings: [UserSettings]
    @State private var showingAddCourse = false
    @State private var showingSettings = false
    @Query private var benches: [StudyBench]
    @State private var originChoice: NodeID?          // nil = use current location
    @State private var classRoute: Route?
    @State private var routeError: String?
    @State private var isRouting = false
    @State private var gapSuggestions: [GapSuggestion] = []

    /// Stable per-minute identity so the advisor task doesn't thrash.
    struct TodayGap: Equatable, Hashable {
        let origin: NodeID
        let start: Date
        let minutes: Int
        let fromCode: String
        let toCode: String
    }

    var body: some View {
        NavigationStack {
            List {
                if let next = nextClass {
                    Section("Next class") {
                        NextClassCard(session: next.session, date: next.date)
                            .listRowInsets(EdgeInsets())
                        if next.session.venue != nil {
                            Picker("From", selection: $originChoice) {
                                Text("Current location").tag(nil as NodeID?)
                                ForEach(env.graph.namedNodes, id: \.id) { node in
                                    Text(node.displayName ?? node.id.rawValue).tag(node.id as NodeID?)
                                }
                            }
                            Button(isRouting ? "Routing…" : "Route to this class") {
                                Task { await routeToClass(next) }
                            }
                            .disabled(isRouting)
                        }
                        if let routeError {
                            Label(routeError, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    if let classRoute {
                        RouteResultSection(route: classRoute)
                        Section {
                            LabeledContent(
                                "Buffer before class",
                                value: bufferText(arrival: classRoute.arrivalTime, classStart: next.date)
                            )
                            Button("Start trip with Live Activity") {
                                Task { await startClassTrip(classRoute, next: next) }
                            }
                            .disabled(env.tripSession.isActive)
                        }
                    }
                }
                if let gap = todaysGap {
                    Section("Free time today · \(gap.minutes) min between \(gap.fromCode) and \(gap.toCode)") {
                        if gapSuggestions.isEmpty {
                            Label("Finding nearby ideas…", systemImage: "sparkles")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(gapSuggestions) { suggestion in
                            HStack(spacing: 12) {
                                Image(systemName: suggestion.icon)
                                    .foregroundStyle(suggestion.category?.tint ?? .green)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                    Text(suggestion.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                ForEach(courses) { course in
                    Section {
                        ForEach(course.sessions.sorted { ($0.dayOfWeek, $0.startMinutes) < ($1.dayOfWeek, $1.startMinutes) }) { session in
                            SessionRow(session: session)
                        }
                    } header: {
                        HStack {
                            Text("\(course.code) · \(course.title)")
                            Spacer()
                            Button(role: .destructive) {
                                modelContext.delete(course)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(course.code)")
                        }
                    }
                }
                if courses.isEmpty {
                    ContentUnavailableView(
                        "No courses yet",
                        systemImage: "calendar.badge.plus",
                        description: Text("Add your first course to see your timetable and next-class routing.")
                    )
                }
            }
            .navigationTitle("Timetable")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add course", systemImage: "plus") { showingAddCourse = true }
                }
            }
            .sheet(isPresented: $showingAddCourse) {
                AddCourseView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .task(id: todaysGap) {
                gapSuggestions = []
                guard let gap = todaysGap else { return }
                let candidates = benches.map {
                    BenchCandidate(graphNodeID: NodeID($0.graphNodeID),
                                   hasPower: $0.hasPower,
                                   isSheltered: $0.isSheltered,
                                   note: $0.note)
                }
                gapSuggestions = await GapPlanner.suggestions(
                    from: gap.origin, gapStart: gap.start, gapMinutes: gap.minutes,
                    benches: candidates, amenities: env.amenities,
                    graph: env.graph, engine: env.routeEngine
                )
            }
        }
    }

    private func routeToClass(_ next: (session: ClassSession, date: Date)) async {
        guard let venue = next.session.venue else { return }
        isRouting = true
        defer { isRouting = false }
        routeError = nil
        classRoute = nil

        guard let origin = await resolveOrigin() else {
            routeError = "No location fix yet — pick a starting point above."
            return
        }
        do {
            classRoute = try await env.routeEngine.route(RouteQuery(
                origin: origin,
                destination: NodeID(venue.graphNodeID),
                departure: .now,
                profile: .fastest
            ))
        } catch RoutingError.unknownNode {
            routeError = "This venue isn't linked to the campus map."
        } catch {
            routeError = "Routing failed: \(error)"
        }
    }

    /// Explicit pick wins; otherwise snap the current GPS fix to the graph,
    /// waiting briefly for a first fix after requesting permission.
    private func resolveOrigin() async -> NodeID? {
        if let originChoice { return originChoice }
        env.location.requestPermission()
        env.location.startUpdates()
        for _ in 0..<6 {
            if let fix = env.location.lastFix {
                return await env.routeEngine.nearestNode(to: fix, where: { !$0.isIndoor })
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    private func startClassTrip(_ route: Route, next: (session: ClassSession, date: Date)) async {
        let from = route.origin.map(env.displayName(for:)) ?? "?"
        let venueName = next.session.venue?.shortName ?? "class"
        let glance = ClassGlance(
            courseCode: next.session.course?.code ?? "?",
            venueShortName: venueName,
            startTime: next.date
        )
        try? await env.tripSession.start(
            route: route,
            summary: "\(from) → \(venueName)",
            nextClass: glance,
            profile: .fastest
        )
        env.beginTripSensing()
    }

    private func bufferText(arrival: Date, classStart: Date) -> String {
        let minutes = Int(classStart.timeIntervalSince(arrival) / 60)
        if minutes >= 0 {
            return "\(minutes) min early"
        }
        return "\(-minutes) min late — leave now!"
    }

    /// First upcoming gap >= 30 min between today's sessions, anchored at the
    /// earlier session's venue. Start time is minute-rounded for identity
    /// stability across body evaluations.
    private var todaysGap: TodayGap? {
        guard let semesterStart = settings.first?.semesterStartDate else { return nil }
        let teaching = TeachingCalendar(semesterStart: semesterStart)
        let calendar = Calendar.current
        let now = Date.now
        guard let week = teaching.teachingWeek(containing: now) else { return nil }
        let weekday = calendar.component(.weekday, from: now)
        let startOfDay = calendar.startOfDay(for: now)

        let today = courses.flatMap(\.sessions)
            .filter { $0.dayOfWeek == weekday && $0.runsInTeachingWeek(week) }
            .sorted { $0.startMinutes < $1.startMinutes }

        for (earlier, later) in zip(today, today.dropFirst()) {
            let earlierEnd = startOfDay.addingTimeInterval(Double((earlier.startMinutes + earlier.durationMinutes) * 60))
            let laterStart = startOfDay.addingTimeInterval(Double(later.startMinutes * 60))
            guard laterStart > now else { continue }               // gap already over
            let rawStart = max(earlierEnd, now)
            let gapStart = Date(timeIntervalSinceReferenceDate: (rawStart.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
            let minutes = Int(laterStart.timeIntervalSince(gapStart) / 60)
            guard minutes >= GapPlanner.minimumGapMinutes,
                  let venueNode = earlier.venue?.graphNodeID else { continue }
            return TodayGap(origin: NodeID(venueNode), start: gapStart, minutes: minutes,
                            fromCode: earlier.course?.code ?? "?", toCode: later.course?.code ?? "?")
        }
        return nil
    }

    private var nextClass: (session: ClassSession, date: Date)? {
        guard let semesterStart = settings.first?.semesterStartDate else { return nil }
        let calendar = TeachingCalendar(semesterStart: semesterStart)
        let now = Date.now
        return courses
            .flatMap(\.sessions)
            .compactMap { session in
                calendar.nextOccurrence(
                    dayOfWeek: session.dayOfWeek,
                    startMinutes: session.startMinutes,
                    teachingWeeksMask: session.teachingWeeksMask,
                    after: now
                ).map { (session, $0) }
            }
            .min { $0.1 < $1.1 }
            .map { (session: $0.0, date: $0.1) }
    }
}

extension Course {
    /// Deterministic per-course identity color from the stored seed.
    var themeColor: Color {
        Color(hue: Double(((colorSeed % 12) + 12) % 12) / 12.0, saturation: 0.62, brightness: 0.70)
    }
}

/// Gradient hero card for the next upcoming session.
struct NextClassCard: View {
    let session: ClassSession
    let date: Date

    var body: some View {
        let color = session.course?.themeColor ?? Brand.navy
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(session.kind.rawValue.capitalized, systemImage: "graduationcap.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.18), in: Capsule())
                Spacer()
                Text(date, style: .relative)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
            }
            Text(session.course?.code ?? "?")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("\(session.course?.title ?? "") · \(session.venue?.shortName ?? "no venue")")
                .font(.subheadline)
                .opacity(0.88)
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [color, color.opacity(0.72)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

struct SessionRow: View {
    let session: ClassSession

    private static let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(Self.dayNames[min(max(session.dayOfWeek, 0), 7)]) \(timeText)")
                Text("\(session.kind.rawValue) · \(session.venue?.shortName ?? "no venue") · \(weeksText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timeText: String {
        String(format: "%02d:%02d", session.startMinutes / 60, session.startMinutes % 60)
    }

    private var weeksText: String {
        switch session.teachingWeeksMask {
        case 0b1_1111_1111_1111: "all weeks"
        case 0b1_0101_0101_0101: "odd weeks"
        case 0b0_1010_1010_1010: "even weeks"
        default: "custom weeks"
        }
    }
}

struct AddCourseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Venue.shortName) private var venues: [Venue]

    @State private var code = ""
    @State private var title = ""
    @State private var kind = SessionKind.lecture
    @State private var dayOfWeek = 2      // Monday
    @State private var startHour = 10
    @State private var durationMinutes = 60
    @State private var weeksPreset = WeeksPreset.all
    @State private var venue: Venue?

    enum WeeksPreset: String, CaseIterable {
        case all = "All", odd = "Odd", even = "Even"
        var mask: Int {
            switch self {
            case .all: 0b1_1111_1111_1111
            case .odd: 0b1_0101_0101_0101
            case .even: 0b0_1010_1010_1010
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Course") {
                    TextField("Code (e.g. SC2005)", text: $code)
                        .textInputAutocapitalization(.characters)
                    TextField("Title", text: $title)
                }
                Section("First session") {
                    Picker("Type", selection: $kind) {
                        ForEach(SessionKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Day", selection: $dayOfWeek) {
                        Text("Mon").tag(2); Text("Tue").tag(3); Text("Wed").tag(4)
                        Text("Thu").tag(5); Text("Fri").tag(6)
                    }
                    Stepper("Starts \(startHour):00", value: $startHour, in: 8...21)
                    Stepper("Duration \(durationMinutes) min", value: $durationMinutes, in: 30...240, step: 30)
                    Picker("Weeks", selection: $weeksPreset) {
                        ForEach(WeeksPreset.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Venue", selection: $venue) {
                        Text("None").tag(nil as Venue?)
                        ForEach(venues) { venue in
                            Text(venue.shortName).tag(venue as Venue?)
                        }
                    }
                }
            }
            .navigationTitle("Add course")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let course = Course(code: code.trimmingCharacters(in: .whitespaces).uppercased(), title: title)
        let session = ClassSession(
            kind: kind,
            dayOfWeek: dayOfWeek,
            startMinutes: startHour * 60,
            durationMinutes: durationMinutes,
            teachingWeeksMask: weeksPreset.mask,
            venue: venue
        )
        course.sessions.append(session)
        modelContext.insert(course)
        dismiss()
    }
}
