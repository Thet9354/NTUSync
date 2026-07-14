import Foundation

/// Pure RFC 5545 iCalendar (`.ics`) serialisation of the expanded semester.
/// Reuses `TimetableEventPlanner`'s dated-event expansion (one VEVENT per
/// occurrence, no RRULEs) so odd/even weeks and the recess week stay correct in
/// any calendar app. No EventKit, no permissions — the output is just text.
nonisolated enum ICSExporter {

    /// UTC timestamp formatter: `yyyyMMdd'T'HHmmss'Z'` (RFC 5545 form 2).
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    /// Serialise planned events into a complete VCALENDAR document.
    /// `now` (injectable for deterministic tests) stamps DTSTAMP.
    static func makeCalendar(from events: [PlannedEvent],
                             calendarName: String = "NTUSync",
                             now: Date = .now) -> String {
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//NTUSync//Timetable Export//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-CALNAME:\(escape(calendarName))",
        ]
        let dtstamp = stamp.string(from: now)
        for (index, event) in events.enumerated() {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(uid(for: event, index: index))")
            lines.append("DTSTAMP:\(dtstamp)")
            lines.append("DTSTART:\(stamp.string(from: event.start))")
            lines.append("DTEND:\(stamp.string(from: event.end))")
            lines.append("SUMMARY:\(escape(event.title))")
            if let location = event.location {
                lines.append("LOCATION:\(escape(location))")
            }
            lines.append("DESCRIPTION:\(escape("Teaching week \(event.teachingWeek) · exported by NTUSync"))")
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        // RFC 5545 mandates CRLF line breaks; fold each line to ≤75 octets.
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// Stable per-occurrence UID: start instant + weekday keep it unique across
    /// re-exports of the same schedule.
    private static func uid(for event: PlannedEvent, index: Int) -> String {
        let seconds = Int(event.start.timeIntervalSince1970)
        return "ntusync-\(seconds)-\(event.teachingWeek)-\(index)@ntusync.app"
    }

    /// Escape TEXT values per RFC 5545 §3.3.11 (backslash, semicolon, comma,
    /// newline). Colons are legal inside TEXT and left alone.
    private static func escape(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "\\", with: "\\\\")
        out = out.replacingOccurrences(of: ";", with: "\\;")
        out = out.replacingOccurrences(of: ",", with: "\\,")
        out = out.replacingOccurrences(of: "\n", with: "\\n")
        return out
    }

    /// Fold a content line to ≤75 octets, continuation lines prefixed with a
    /// single space (RFC 5545 §3.1). Folds on UTF-8 byte boundaries.
    static func fold(_ line: String) -> String {
        let bytes = Array(line.utf8)
        guard bytes.count > 75 else { return line }
        var result = Data()
        var index = 0
        var isFirst = true
        while index < bytes.count {
            // 75 octets on the first line; 74 on continuations (leading space).
            let limit = isFirst ? 75 : 74
            var take = min(limit, bytes.count - index)
            // Don't split a multi-byte UTF-8 scalar across a fold boundary.
            while take > 0 && index + take < bytes.count && isContinuationByte(bytes[index + take]) {
                take -= 1
            }
            if !isFirst { result.append(0x20) } // leading space
            result.append(contentsOf: bytes[index..<(index + take)])
            index += take
            if index < bytes.count { result.append(contentsOf: [0x0D, 0x0A]) }
            isFirst = false
        }
        return String(decoding: result, as: UTF8.self)
    }

    /// True if `bytes[i]` is a UTF-8 continuation byte (10xxxxxx); guards the
    /// out-of-range case at the very end of the buffer.
    private static func isContinuationByte(_ byte: UInt8) -> Bool {
        byte & 0xC0 == 0x80
    }
}
