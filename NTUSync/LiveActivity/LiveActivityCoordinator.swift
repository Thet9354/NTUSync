import Foundation
import ActivityKit
import os

nonisolated enum LiveActivityError: Error, Equatable {
    case activitiesDisabled
    case noActiveTrip
    case requestFailed(String)
}

nonisolated enum ActivityDismissal: Equatable, Sendable {
    case immediate
    case after(Date)
}

/// Seam between the coordinator and ActivityKit so the transaction rules are
/// unit-testable without Springboard.
@MainActor
protocol TripActivityGateway {
    var areActivitiesEnabled: Bool { get }
    func existingActivityIDs() -> [String]
    func start(attributes: TripActivityAttributes,
               state: TripActivityAttributes.ContentState,
               staleDate: Date) throws -> String
    func update(id: String, state: TripActivityAttributes.ContentState,
                staleDate: Date, relevanceScore: Double) async
    func end(id: String, state: TripActivityAttributes.ContentState?,
             dismissal: ActivityDismissal) async
}

@MainActor
final class ActivityKitGateway: TripActivityGateway {

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func existingActivityIDs() -> [String] {
        Activity<TripActivityAttributes>.activities.map(\.id)
    }

    func start(attributes: TripActivityAttributes,
               state: TripActivityAttributes.ContentState,
               staleDate: Date) throws -> String {
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: staleDate, relevanceScore: 100)
            )
            return activity.id
        } catch {
            throw LiveActivityError.requestFailed(String(describing: error))
        }
    }

    func update(id: String, state: TripActivityAttributes.ContentState,
                staleDate: Date, relevanceScore: Double) async {
        // Activity is non-Sendable and its update/end methods are @concurrent,
        // so both the registry lookup and the call must stay off-actor.
        await Task.detached {
            guard let activity = Activity<TripActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            await activity.update(ActivityContent(state: state, staleDate: staleDate, relevanceScore: relevanceScore))
        }.value
    }

    func end(id: String, state: TripActivityAttributes.ContentState?, dismissal: ActivityDismissal) async {
        await Task.detached {
            guard let activity = Activity<TripActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            let content = state.map { ActivityContent(state: $0, staleDate: nil) }
            switch dismissal {
            case .immediate: await activity.end(content, dismissalPolicy: .immediate)
            case .after(let date): await activity.end(content, dismissalPolicy: .after(date))
            }
        }.value
    }
}

/// The only type allowed to touch ActivityKit. Enforces the transaction rules:
/// single-activity invariant, orphan sweep, enablement gate, de-duplicated
/// pushes, stale dating, phase-based relevance.
@MainActor
@Observable
final class LiveActivityCoordinator {
    private let gateway: any TripActivityGateway
    private(set) var activityID: String?
    private var lastPushedState: TripActivityAttributes.ContentState?
    /// Exposed so tests (and the week-8 verification gate) can assert the
    /// <= 6 pushes-per-trip budget.
    private(set) var pushCount = 0

    var isActive: Bool { activityID != nil }

    init(gateway: any TripActivityGateway = ActivityKitGateway()) {
        self.gateway = gateway
    }

    func begin(attributes: TripActivityAttributes,
               initialState: TripActivityAttributes.ContentState,
               staleAfter: TimeInterval = 90) async throws {
        guard gateway.areActivitiesEnabled else {
            Logger.liveActivity.notice("live activities disabled; degrading to in-app banner")
            throw LiveActivityError.activitiesDisabled
        }
        // Orphan sweep: activities surviving a crash of a previous process.
        for orphan in gateway.existingActivityIDs() {
            Logger.liveActivity.notice("ending orphan activity \(orphan)")
            await gateway.end(id: orphan, state: nil, dismissal: .immediate)
        }
        let id = try gateway.start(
            attributes: attributes,
            state: initialState,
            staleDate: Date(timeIntervalSinceNow: staleAfter)
        )
        activityID = id
        lastPushedState = initialState
        pushCount = 1
        Logger.liveActivity.info("began activity \(id) [\(attributes.routeSummary)]")
    }

    /// Reattach to an activity that survived an app relaunch. Returns false
    /// when the activity no longer exists (it was dismissed or expired).
    func rebind(activityID id: String) -> Bool {
        guard gateway.existingActivityIDs().contains(id) else { return false }
        activityID = id
        lastPushedState = nil   // force the next push through
        pushCount = 1
        Logger.liveActivity.info("rebound to surviving activity \(id)")
        return true
    }

    func push(_ state: TripActivityAttributes.ContentState, staleAfter: TimeInterval = 90) async {
        guard let id = activityID else { return }
        guard state != lastPushedState else {
            Logger.liveActivity.debug("push de-duplicated (state unchanged)")
            return
        }
        let relevance: Double = state.phase == .waitingForBus ? 100 : 50
        await gateway.update(
            id: id, state: state,
            staleDate: Date(timeIntervalSinceNow: staleAfter),
            relevanceScore: relevance
        )
        lastPushedState = state
        pushCount += 1
        Logger.liveActivity.info("pushed \(state.phase.rawValue) (push #\(self.pushCount))")
    }

    func end(finalState: TripActivityAttributes.ContentState?, dismissal: ActivityDismissal = .after(Date(timeIntervalSinceNow: 300))) async {
        guard let id = activityID else { return }
        await gateway.end(id: id, state: finalState, dismissal: dismissal)
        Logger.liveActivity.info("ended activity \(id) after \(self.pushCount) pushes")
        activityID = nil
        lastPushedState = nil
    }
}
