import Foundation
import UserNotifications
import os

/// Owns the "leave now" local notifications: computes route time from the
/// user's hall to each upcoming class with the route engine and schedules a
/// notification at `classStart − routeTime − buffer`. Also the app's
/// notification delegate, so a tapped alert deep-links into the trip flow.
@MainActor
final class LeaveAlertScheduler: NSObject, UNUserNotificationCenterDelegate {
    private static let idPrefix = "leave."
    private let center = UNUserNotificationCenter.current()

    /// Set by the composition root; fired when the user taps a leave alert.
    var onOpenDestination: ((NodeID) -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    /// Recompute the pending alert window from scratch. Always clears our own
    /// pending alerts first, so disabling the feature is also a cleanup.
    func reschedule(
        sessions: [SessionSnapshot],
        semesterStart: Date,
        homeNodeID: String?,
        bufferMinutes: Int,
        enabled: Bool,
        engine: RouteEngine
    ) async {
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        guard enabled, let homeNodeID else { return }
        let home = NodeID(homeNodeID)

        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
            Logger.persistence.notice("leave alerts: notification authorization declined")
            return
        }

        let now = Date.now
        let occurrences = LeaveAlertPlanner.upcomingOccurrences(
            sessions: sessions, semesterStart: semesterStart, now: now
        )

        var scheduled = 0
        for (session, classStart) in occurrences {
            guard let venueNodeID = session.venueNodeID else { continue }
            let destination = NodeID(venueNodeID)
            guard destination != home else { continue }

            // Route time depends on departure (shuttle headways vary by time of
            // day), and departure depends on route time — one refinement pass
            // settles it well within the buffer's tolerance.
            guard let probe = try? await engine.route(RouteQuery(
                origin: home, destination: destination,
                departure: classStart, profile: .fastest
            )) else { continue }
            let refinedDeparture = LeaveAlertPlanner.fireDate(
                classStart: classStart, travelSeconds: probe.totalSeconds, bufferMinutes: bufferMinutes
            )
            guard let route = try? await engine.route(RouteQuery(
                origin: home, destination: destination,
                departure: max(refinedDeparture, now), profile: .fastest
            )) else { continue }

            let fireDate = LeaveAlertPlanner.fireDate(
                classStart: classStart, travelSeconds: route.totalSeconds, bufferMinutes: bufferMinutes
            )
            guard fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Leave for \(session.courseCode) — \(Int(route.totalSeconds / 60)) min \(routeSummary(route))"
            let startText = classStart.formatted(date: .omitted, time: .shortened)
            if let venueName = session.venueName {
                content.body = "\(session.kind.rawValue.capitalized) starts \(startText) at \(venueName). \(bufferMinutes) min buffer included."
            } else {
                content.body = "\(session.kind.rawValue.capitalized) starts \(startText). \(bufferMinutes) min buffer included."
            }
            content.sound = .default
            content.userInfo = ["destinationNodeID": venueNodeID]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: fireDate
            )
            let request = UNNotificationRequest(
                identifier: "\(Self.idPrefix)\(session.courseCode).\(Int(classStart.timeIntervalSince1970))",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            do {
                try await center.add(request)
                scheduled += 1
            } catch {
                Logger.persistence.error("leave alerts: add failed: \(String(describing: error))")
            }
        }
        Logger.persistence.info("leave alerts: scheduled \(scheduled) of \(occurrences.count) occurrences")
    }

    private func routeSummary(_ route: Route) -> String {
        if let line = route.legs.first(where: { $0.kind == .shuttle })?.line {
            return "via \(line.rawValue)"
        }
        return "on foot"
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let raw = response.notification.request.content.userInfo["destinationNodeID"] as? String else {
            return
        }
        await MainActor.run {
            onOpenDestination?(NodeID(raw))
        }
    }
}
