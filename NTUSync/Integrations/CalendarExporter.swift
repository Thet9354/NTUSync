import Foundation
import EventKit
import os

nonisolated enum CalendarExportError: Error, Equatable {
    case accessDenied
    case noWritableSource
    case nothingToExport
}

/// Thin EventKit adapter: owns a dedicated "NTUSync" calendar and rewrites it
/// wholesale on every sync. Uses write-only access (softer prompt); because
/// write-only access cannot *read* events, re-sync deletes and recreates the
/// whole calendar instead of diffing — our calendar holds nothing but our own
/// exported timetable, so this is lossless.
@MainActor
final class CalendarExporter {
    private let store = EKEventStore()
    private static let calendarTitle = "NTUSync"
    private static let calendarIDKey = "calendarExport.calendarIdentifier"

    /// Exports the planned events, replacing any previous export.
    /// Returns the number of events written.
    func export(_ events: [PlannedEvent]) async throws -> Int {
        guard !events.isEmpty else { throw CalendarExportError.nothingToExport }

        let granted = try await store.requestWriteOnlyAccessToEvents()
        guard granted else { throw CalendarExportError.accessDenied }

        let calendar = try replaceCalendar()
        for planned in events {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = planned.title
            event.location = planned.location
            event.startDate = planned.start
            event.endDate = planned.end
            event.notes = "Teaching week \(planned.teachingWeek) · exported by NTUSync"
            try store.save(event, span: .thisEvent, commit: false)
        }
        try store.commit()
        Logger.persistence.info("calendar export: wrote \(events.count) events")
        return events.count
    }

    /// Drop the previous NTUSync calendar (if any) and create a fresh one.
    private func replaceCalendar() throws -> EKCalendar {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: Self.calendarIDKey),
           let stale = store.calendar(withIdentifier: id) {
            try store.removeCalendar(stale, commit: true)
            Logger.persistence.debug("calendar export: removed previous calendar")
        }

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.calendarTitle
        calendar.cgColor = CGColor(red: 0.77, green: 0.06, blue: 0.19, alpha: 1) // NTU red
        guard let source = store.defaultCalendarForNewEvents?.source
                ?? store.sources.first(where: { $0.sourceType == .local })
                ?? store.sources.first else {
            throw CalendarExportError.noWritableSource
        }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        defaults.set(calendar.calendarIdentifier, forKey: Self.calendarIDKey)
        return calendar
    }
}
