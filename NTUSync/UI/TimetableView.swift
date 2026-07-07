import SwiftUI
import SwiftData

struct TimetableView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.code) private var courses: [Course]
    @Query private var settings: [UserSettings]
    @State private var showingAddCourse = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                if let next = nextClass {
                    Section("Next class") {
                        VStack(alignment: .leading) {
                            Text("\(next.session.course?.code ?? "?") \(next.session.kind.rawValue)")
                                .font(.headline)
                            Text("\(next.date.formatted(date: .abbreviated, time: .shortened)) · \(next.session.venue?.shortName ?? "no venue")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
        }
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
