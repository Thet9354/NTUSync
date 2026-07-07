import Foundation
import os

/// A point in the weekly service cycle: `weekday` follows `Calendar` convention
/// (1 = Sunday … 7 = Saturday), `secondsIntoDay` in [0, 86400).
nonisolated struct WeekTimePoint: Sendable, Hashable {
    var weekday: Int
    var secondsIntoDay: Double

    func advanced(bySeconds seconds: Double) -> WeekTimePoint {
        var total = secondsIntoDay + seconds
        var day = weekday
        while total >= 86_400 {
            total -= 86_400
            day = day % 7 + 1
        }
        return WeekTimePoint(weekday: day, secondsIntoDay: total)
    }

    static func from(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> WeekTimePoint {
        let weekday = calendar.component(.weekday, from: date)
        let start = calendar.startOfDay(for: date)
        return WeekTimePoint(weekday: weekday, secondsIntoDay: date.timeIntervalSince(start))
    }
}

nonisolated struct ShuttleTimetable: Sendable {
    struct ServicePeriod: Codable, Sendable {
        let days: [Int]            // Calendar weekdays, 1 = Sunday
        let startMinute: Int       // minutes from midnight, inclusive
        let endMinute: Int         // exclusive
        let headwayMinutes: Double
    }

    struct Line: Codable, Sendable {
        let id: ShuttleLineID
        let displayName: String
        let periods: [ServicePeriod]
    }

    let validUntil: String
    let shuttleSpeedMetresPerSecond: Double
    let dwellSeconds: Double
    private let linesByID: [ShuttleLineID: Line]

    var lines: [Line] { Array(linesByID.values) }

    init(validUntil: String, shuttleSpeed: Double, dwellSeconds: Double, lines: [Line]) {
        self.validUntil = validUntil
        self.shuttleSpeedMetresPerSecond = shuttleSpeed
        self.dwellSeconds = dwellSeconds
        self.linesByID = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) })
    }

    func line(_ id: ShuttleLineID) -> Line? { linesByID[id] }

    /// Expected boarding wait in seconds under the uniform-arrival assumption
    /// (headway / 2), or nil when the line is not running at `time`.
    func expectedWaitSeconds(line id: ShuttleLineID, at time: WeekTimePoint) -> Double? {
        guard let line = linesByID[id] else { return nil }
        let minute = time.secondsIntoDay / 60
        for period in line.periods
        where period.days.contains(time.weekday)
            && minute >= Double(period.startMinute)
            && minute < Double(period.endMinute) {
            return period.headwayMinutes * 60 / 2
        }
        return nil
    }

    /// In-vehicle time for one shuttle edge, including the stop dwell.
    func rideSeconds(forEdgeLength lengthMetres: Double) -> Double {
        lengthMetres / shuttleSpeedMetresPerSecond + dwellSeconds
    }

    // MARK: Loading

    private struct Document: Codable {
        let formatVersion: Int
        let validUntil: String
        let shuttleSpeedMetresPerSecond: Double
        let dwellSeconds: Double
        let lines: [Line]
    }

    static func loadBundled(_ bundle: Bundle = .main) throws -> ShuttleTimetable {
        guard let url = bundle.url(forResource: "ShuttleTimetable", withExtension: "json") else {
            Logger.routing.fault("ShuttleTimetable.json missing from bundle")
            throw GraphLoadingError.resourceMissing("ShuttleTimetable.json")
        }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        guard document.formatVersion == 1 else {
            throw GraphLoadingError.malformed("unsupported timetable formatVersion \(document.formatVersion)")
        }
        Logger.routing.info("Loaded shuttle timetable: \(document.lines.count) lines, valid until \(document.validUntil)")
        return ShuttleTimetable(
            validUntil: document.validUntil,
            shuttleSpeed: document.shuttleSpeedMetresPerSecond,
            dwellSeconds: document.dwellSeconds,
            lines: document.lines
        )
    }
}
