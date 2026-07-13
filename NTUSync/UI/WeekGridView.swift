import SwiftUI
import SwiftData

/// Sendable projection of a session for the grid (models stay on @MainActor;
/// the grid math is pure and testable).
nonisolated struct WeekGridSession: Sendable, Hashable, Identifiable {
    let courseCode: String
    let colorSeed: Int
    let kind: SessionKind
    let dayOfWeek: Int          // Calendar weekday, 1 = Sunday … 7 = Saturday
    let startMinutes: Int
    let durationMinutes: Int
    let teachingWeeksMask: Int
    let venueShortName: String?

    var id: String { "\(courseCode).\(kind.rawValue).\(dayOfWeek).\(startMinutes)" }

    func runsInTeachingWeek(_ week: Int) -> Bool {
        (1...13).contains(week) && teachingWeeksMask & (1 << (week - 1)) != 0
    }
}

/// Pure layout math for the 13-week × weekday matrix.
nonisolated enum WeekGrid {

    /// Mon–Fri always; Saturday/Sunday columns only when a session uses them.
    static func weekdayColumns(for sessions: [WeekGridSession]) -> [Int] {
        var columns = [2, 3, 4, 5, 6]
        if sessions.contains(where: { $0.dayOfWeek == 7 }) { columns.append(7) }
        if sessions.contains(where: { $0.dayOfWeek == 1 }) { columns.append(1) }
        return columns
    }

    /// Sessions occupying one grid cell, chronological.
    static func entries(week: Int, weekday: Int, sessions: [WeekGridSession]) -> [WeekGridSession] {
        sessions
            .filter { $0.dayOfWeek == weekday && $0.runsInTeachingWeek(week) }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    /// Monday date of a teaching week (weeks 1–7 are calendar weeks 0–6,
    /// recess occupies calendar week 7, weeks 8–13 are calendar weeks 8–13) —
    /// the same mapping the calendar exporter uses.
    static func mondayDate(ofTeachingWeek week: Int, semesterStart: Date,
                           calendar: Calendar = .current) -> Date? {
        guard (1...13).contains(week) else { return nil }
        let calendarWeek = week <= 7 ? week - 1 : week
        return calendar.date(byAdding: .day, value: calendarWeek * 7,
                             to: calendar.startOfDay(for: semesterStart))
    }
}

@MainActor
extension WeekGridSession {
    static func sessions(of courses: [Course]) -> [WeekGridSession] {
        courses.flatMap { course in
            course.sessions.map { session in
                WeekGridSession(
                    courseCode: course.code,
                    colorSeed: course.colorSeed,
                    kind: session.kind,
                    dayOfWeek: session.dayOfWeek,
                    startMinutes: session.startMinutes,
                    durationMinutes: session.durationMinutes,
                    teachingWeeksMask: session.teachingWeeksMask,
                    venueShortName: session.venue?.shortName
                )
            }
        }
    }

    var themeColor: Color {
        Color(hue: Double(((colorSeed % 12) + 12) % 12) / 12.0, saturation: 0.62, brightness: 0.70)
    }
}

/// 13-week × weekday matrix: one row per teaching week (recess called out
/// between 7 and 8), one dot per session, so odd/even-week patterns are
/// visible at a glance. Tap a cell for the day's detail.
struct WeekGridView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Course.code) private var courses: [Course]
    @Query private var settings: [UserSettings]

    @State private var selectedCell: SelectedCell?

    private struct SelectedCell: Identifiable {
        let week: Int
        let weekday: Int
        var id: String { "\(week).\(weekday)" }
    }

    private static let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        let sessions = WeekGridSession.sessions(of: courses)
        let columns = WeekGrid.weekdayColumns(for: sessions)
        let currentWeek = settings.first.flatMap {
            TeachingCalendar(semesterStart: $0.semesterStartDate).teachingWeek(containing: .now)
        }

        NavigationStack {
            ScrollView {
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow {
                        Text("Wk")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .leading)
                        ForEach(columns, id: \.self) { weekday in
                            Text(Self.dayNames[weekday])
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(1...13, id: \.self) { week in
                        if week == 8 {
                            GridRow {
                                Text("Recess week")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemFill).opacity(0.5),
                                                in: RoundedRectangle(cornerRadius: 6))
                                    .gridCellColumns(columns.count + 1)
                            }
                        }
                        weekRow(week: week, columns: columns, sessions: sessions,
                                isCurrent: week == currentWeek)
                    }
                }
                .padding(12)

                legend
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            .navigationTitle("Semester grid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedCell) { cell in
                cellDetail(cell, sessions: sessions)
                    .presentationDetents([.medium])
            }
            .overlay {
                if courses.isEmpty {
                    ContentUnavailableView(
                        "No courses yet",
                        systemImage: "square.grid.3x3",
                        description: Text("Add courses to see the semester pattern.")
                    )
                }
            }
        }
    }

    private func weekRow(week: Int, columns: [Int],
                         sessions: [WeekGridSession], isCurrent: Bool) -> some View {
        GridRow {
            VStack(alignment: .leading, spacing: 0) {
                Text("W\(week)")
                    .font(.caption.weight(isCurrent ? .bold : .regular))
                if let monday = mondayDate(ofWeek: week) {
                    Text(monday, format: .dateTime.day().month(.abbreviated))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 52, alignment: .leading)
            ForEach(columns, id: \.self) { weekday in
                let entries = WeekGrid.entries(week: week, weekday: weekday, sessions: sessions)
                cellView(entries: entries, isCurrent: isCurrent)
                    .onTapGesture {
                        if !entries.isEmpty {
                            selectedCell = SelectedCell(week: week, weekday: weekday)
                        }
                    }
            }
        }
    }

    private func cellView(entries: [WeekGridSession], isCurrent: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(entries.prefix(4)) { entry in
                Circle()
                    .fill(entry.themeColor)
                    .frame(width: 7, height: 7)
            }
            if entries.count > 4 {
                Text("+\(entries.count - 4)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 26)
        .background(
            isCurrent ? Brand.navy.opacity(0.14) : Color(.systemFill).opacity(0.35),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    private var legend: some View {
        FlowLegend(items: courses.map { ($0.code, $0.themeColor) })
    }

    private func cellDetail(_ cell: SelectedCell, sessions: [WeekGridSession]) -> some View {
        let entries = WeekGrid.entries(week: cell.week, weekday: cell.weekday, sessions: sessions)
        return NavigationStack {
            List(entries) { entry in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(entry.themeColor)
                        .frame(width: 4, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.courseCode) · \(entry.kind.rawValue.capitalized)")
                            .font(.subheadline.weight(.semibold))
                        Text("\(timeText(entry.startMinutes))–\(timeText(entry.startMinutes + entry.durationMinutes)) · \(entry.venueShortName ?? "no venue")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("\(Self.dayNames[cell.weekday]) · week \(cell.week)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func mondayDate(ofWeek week: Int) -> Date? {
        settings.first.flatMap {
            WeekGrid.mondayDate(ofTeachingWeek: week, semesterStart: $0.semesterStartDate)
        }
    }

    private func timeText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

/// Wrapping legend row of course color swatches.
private struct FlowLegend: View {
    let items: [(String, Color)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(items, id: \.0) { code, color in
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(code)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
