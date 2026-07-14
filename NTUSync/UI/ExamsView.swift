import SwiftUI
import SwiftData

/// One-off exam events with a countdown: hero card for the next exam,
/// upcoming/completed sections, swipe-to-delete. All countdown math lives in
/// the pure `ExamPlanner`.
struct ExamsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExamEvent.date) private var exams: [ExamEvent]
    @Query(sort: \Course.code) private var courses: [Course]

    @State private var showingAddExam = false
    /// Minute-tick anchor so countdown badges stay fresh while the sheet is up.
    @State private var now = Date.now

    var body: some View {
        let upcoming = exams.filter { now < $0.snapshot.end }
        let completed = exams.filter { now >= $0.snapshot.end }.reversed()

        NavigationStack {
            List {
                if let next = upcoming.first {
                    Section {
                        ExamHeroCard(exam: next, now: now, color: color(for: next))
                            .listRowInsets(EdgeInsets())
                    }
                }
                if !upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcoming) { exam in
                            ExamRow(exam: exam, now: now)
                        }
                        .onDelete { delete(Array(upcoming), at: $0) }
                    }
                }
                if !completed.isEmpty {
                    Section("Completed") {
                        ForEach(Array(completed)) { exam in
                            ExamRow(exam: exam, now: now)
                                .foregroundStyle(.secondary)
                        }
                        .onDelete { delete(Array(completed), at: $0) }
                    }
                }
            }
            .navigationTitle("Exams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add exam", systemImage: "plus") { showingAddExam = true }
                }
            }
            .sheet(isPresented: $showingAddExam) {
                AddExamView()
            }
            .overlay {
                if exams.isEmpty {
                    ContentUnavailableView(
                        "No exams yet",
                        systemImage: "hourglass",
                        description: Text("Add your finals — date, venue, and the seat number you'll forget.")
                    )
                }
            }
            .task {
                // Tick once a minute so "today · in 42 min" doesn't go stale.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    now = .now
                }
            }
        }
    }

    private func color(for exam: ExamEvent) -> Color {
        courses.first { $0.code == exam.courseCode }?.themeColor ?? Brand.navy
    }

    private func delete(_ source: [ExamEvent], at offsets: IndexSet) {
        for index in offsets { modelContext.delete(source[index]) }
    }
}

extension ExamEvent {
    /// Sendable projection for the pure countdown math.
    var snapshot: ExamSnapshot {
        ExamSnapshot(courseCode: courseCode, date: date, durationMinutes: durationMinutes,
                     venueName: venueName, seatNumber: seatNumber)
    }
}

extension ExamPhase {
    /// Human badge text for a countdown chip.
    var label: String {
        switch self {
        case .upcoming(let days): days == 1 ? "tomorrow" : "in \(days) days"
        case .today(let minutes): minutes < 60 ? "today · in \(minutes) min"
                                               : "today · in \(minutes / 60) h \(minutes % 60) min"
        case .inProgress(let remaining): "in progress · \(remaining) min left"
        case .finished: "done"
        }
    }
}

/// Gradient countdown card for the soonest exam, matching the next-class hero.
private struct ExamHeroCard: View {
    let exam: ExamEvent
    let now: Date
    let color: Color

    var body: some View {
        let phase = ExamPlanner.phase(of: exam.snapshot, now: now)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Next exam", systemImage: "hourglass")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.18), in: Capsule())
                Spacer()
                Text(phase.label)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
            }
            Text(exam.courseCode)
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text(detailLine)
                .font(.subheadline)
                .opacity(0.88)
            Text(exam.date.formatted(date: .abbreviated, time: .shortened))
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

    private var detailLine: String {
        var parts = [exam.venueName ?? "venue TBC"]
        if let seat = exam.seatNumber, !seat.isEmpty { parts.append("seat \(seat)") }
        parts.append("\(exam.durationMinutes) min")
        return parts.joined(separator: " · ")
    }
}

private struct ExamRow: View {
    let exam: ExamEvent
    let now: Date

    var body: some View {
        let phase = ExamPlanner.phase(of: exam.snapshot, now: now)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(exam.courseCode)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(phase.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemFill).opacity(0.6), in: Capsule())
        }
    }

    private var subtitle: String {
        var parts = [exam.date.formatted(date: .abbreviated, time: .shortened)]
        if let venue = exam.venueName, !venue.isEmpty { parts.append(venue) }
        if let seat = exam.seatNumber, !seat.isEmpty { parts.append("seat \(seat)") }
        return parts.joined(separator: " · ")
    }
}

struct AddExamView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Course.code) private var courses: [Course]

    @State private var courseCode = ""
    @State private var date = Calendar.current.date(
        bySettingHour: 9, minute: 0, second: 0, of: .now.addingTimeInterval(7 * 86_400)) ?? .now
    @State private var durationMinutes = 120
    @State private var venueName = ""
    @State private var seatNumber = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Exam") {
                    TextField("Course code (e.g. SC2005)", text: $courseCode)
                        .textInputAutocapitalization(.characters)
                    if !courses.isEmpty {
                        // One-tap prefill from the timetable.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(courses) { course in
                                    Button(course.code) { courseCode = course.code }
                                        .font(.caption.weight(.semibold))
                                        .buttonStyle(.bordered)
                                        .buttonBorderShape(.capsule)
                                        .tint(course.themeColor)
                                }
                            }
                        }
                    }
                    DatePicker("Starts", selection: $date)
                    Stepper("Duration \(durationMinutes) min", value: $durationMinutes, in: 30...300, step: 30)
                }
                Section("Where") {
                    TextField("Venue (e.g. Sports & Rec Centre)", text: $venueName)
                    TextField("Seat number", text: $seatNumber)
                }
            }
            .navigationTitle("Add exam")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(courseCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedVenue = venueName.trimmingCharacters(in: .whitespaces)
        let trimmedSeat = seatNumber.trimmingCharacters(in: .whitespaces)
        modelContext.insert(ExamEvent(
            courseCode: courseCode.trimmingCharacters(in: .whitespaces).uppercased(),
            date: date,
            durationMinutes: durationMinutes,
            venueName: trimmedVenue.isEmpty ? nil : trimmedVenue,
            seatNumber: trimmedSeat.isEmpty ? nil : trimmedSeat
        ))
        dismiss()
    }
}
