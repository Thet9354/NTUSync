import Foundation
import os

/// Orchestrates one active trip: phase machine + autopilot + dead reckoning +
/// Live Activity pushes. Steps are coalesced into the next phase push, never
/// pushed alone.
@MainActor
@Observable
final class TripSessionCoordinator {
    private let liveActivity: LiveActivityCoordinator
    private let snapshots: TripSnapshotStore

    private(set) var route: Route?
    private(set) var machine: TripStateMachine?
    private(set) var nextClass: ClassGlance?
    private(set) var profile: TravelProfile?
    private(set) var estimator: RouteProgressEstimator?
    private var autopilot: TripAutopilot?
    private var summary = ""
    private var stepsSoFar = 0

    /// Resolves graph node coordinates; injected by AppEnvironment.
    var nodeLocator: ((NodeID) -> GeoPoint?)?
    /// Fired when a re-acquired fix disagrees with the estimate beyond the
    /// replan threshold; the owner re-routes from the fix.
    var onReplanNeeded: ((GeoPoint) -> Void)?

    var phase: TripPhase? { machine?.phase }
    var isActive: Bool { machine != nil }
    var progressFraction: Double? { estimator?.fractionComplete }
    var isDeadReckoning: Bool { estimator?.isDeadReckoning ?? false }

    init(liveActivity: LiveActivityCoordinator, snapshots: TripSnapshotStore = TripSnapshotStore()) {
        self.liveActivity = liveActivity
        self.snapshots = snapshots
    }

    // MARK: Lifecycle

    func start(route: Route, summary: String, nextClass: ClassGlance?, profile: TravelProfile = .fastest) async throws {
        if isActive {
            await end()
        }
        let initialPhase: TripPhase = route.legs.contains { $0.kind == .shuttle }
            ? .walkingToStop
            : .walkingToClass
        install(route: route, summary: summary, nextClass: nextClass, profile: profile,
                phase: initialPhase, steps: 0)

        let attributes = TripActivityAttributes(
            routeSummary: summary,
            destinationNodeID: route.destination?.rawValue ?? ""
        )
        do {
            try await liveActivity.begin(attributes: attributes, initialState: contentState(for: initialPhase))
        } catch LiveActivityError.activitiesDisabled {
            // Degraded mode: trip still runs in-app without a Live Activity.
            Logger.liveActivity.notice("trip running without live activity")
        }
        persistSnapshot()
    }

    /// Rebind to a trip that survived an app relaunch (design spec §5.4).
    /// Returns true when a surviving Live Activity was reattached.
    @discardableResult
    func restoreIfPossible() -> Bool {
        guard !isActive, let snapshot = snapshots.load() else { return false }
        guard let activityID = snapshot.activityID,
              liveActivity.rebind(activityID: activityID) else {
            Logger.liveActivity.notice("stale trip snapshot discarded (no surviving activity)")
            snapshots.clear()
            return false
        }
        install(route: snapshot.route, summary: snapshot.summary, nextClass: snapshot.nextClass,
                profile: .fastest, phase: snapshot.phase, steps: snapshot.stepsSoFar)
        Logger.liveActivity.info("restored active trip at phase \(snapshot.phase.rawValue)")
        return true
    }

    func advance(to next: TripPhase) async throws(TripStateError) {
        guard var machine else { throw .illegalTransition(from: .arrived, to: next) }
        try machine.advance(to: next)
        self.machine = machine
        await liveActivity.push(contentState(for: machine.phase))
        if machine.phase == .arrived {
            await end()
        } else {
            persistSnapshot()
        }
    }

    func end() async {
        if let machine {
            await liveActivity.end(finalState: contentState(for: machine.phase))
        }
        snapshots.clear()
        route = nil
        machine = nil
        nextClass = nil
        profile = nil
        autopilot = nil
        estimator = nil
    }

    /// Swap in a re-planned route mid-trip (missed bus, user deviated).
    func updateRoute(_ newRoute: Route) async {
        guard let machine else { return }
        route = newRoute
        autopilot = TripAutopilot(route: newRoute)
        estimator = RouteProgressEstimator(
            routeLengthMetres: newRoute.legs.reduce(0) { $0 + $1.metres }
        )
        Logger.routing.notice("trip re-planned; new arrival \(newRoute.arrivalTime)")
        await liveActivity.push(contentState(for: machine.phase))
        persistSnapshot()
    }

    // MARK: Sensor ingestion

    /// GPS fix pipeline: reconcile dead reckoning, then let the autopilot
    /// decide whether the trip advances.
    func ingest(fix: GeoPoint, accuracy: Double) {
        guard isActive, let autopilot, let machine else { return }

        if var estimator = self.estimator {
            if let along = autopilot.projectOntoRoute(fix: fix, locate: locate) {
                let wasDeadReckoning = estimator.isDeadReckoning
                let outcome = estimator.reconcile(fixDistanceAlong: along, accuracy: accuracy)
                self.estimator = estimator
                if wasDeadReckoning, case .replanSuggested(let drift) = outcome {
                    Logger.location.notice("dr.reconciled driftMetres=\(Int(drift)) -> replan")
                    onReplanNeeded?(fix)
                    return
                }
            } else if !estimator.isDeadReckoning, accuracy >= 0, accuracy <= TripAutopilot.maxUsableAccuracy {
                // Confident fix nowhere near the route: the user left it.
                Logger.location.notice("fix off-corridor -> replan")
                onReplanNeeded?(fix)
                return
            }
        }

        if let next = autopilot.suggestedTransition(
            from: machine.phase, fix: fix, accuracy: accuracy, locate: locate
        ) {
            Logger.location.info("autopilot: \(machine.phase.rawValue) -> \(next.rawValue)")
            Task { try? await self.advance(to: next) }
        }
    }

    func setGPSDenied(_ denied: Bool) {
        guard isActive, denied else { return }
        estimator?.beginDeadReckoning()
        Logger.location.notice("gps.denied -> dr.engaged")
    }

    /// Pedometer distance delta advances the 1-D route estimate.
    func recordDistanceDelta(_ metres: Double) {
        estimator?.advance(byMetres: metres)
    }

    /// Fold pedometer progress into local state; surfaced on the next push.
    func recordSteps(_ total: Int) {
        stepsSoFar = total
    }

    // MARK: Internals

    private func install(route: Route, summary: String, nextClass: ClassGlance?,
                         profile: TravelProfile, phase: TripPhase, steps: Int) {
        self.route = route
        self.summary = summary
        self.nextClass = nextClass
        self.profile = profile
        self.machine = TripStateMachine(initial: phase)
        self.stepsSoFar = steps
        self.autopilot = TripAutopilot(route: route)
        self.estimator = RouteProgressEstimator(
            routeLengthMetres: route.legs.reduce(0) { $0 + $1.metres }
        )
    }

    private func locate(_ node: NodeID) -> GeoPoint? {
        nodeLocator?(node)
    }

    private func persistSnapshot() {
        guard let route, let machine else { return }
        snapshots.save(ActiveTripSnapshot(
            activityID: liveActivity.activityID,
            route: route,
            summary: summary,
            phase: machine.phase,
            stepsSoFar: stepsSoFar,
            nextClass: nextClass
        ))
    }

    private func contentState(for phase: TripPhase) -> TripActivityAttributes.ContentState {
        let shuttleLeg = route?.legs.first { $0.kind == .shuttle }
        var boardingWindow: ClosedRange<Date>?
        if let boarding = shuttleLeg?.boardingTime, phase == .walkingToStop || phase == .waitingForBus {
            boardingWindow = boarding...boarding.addingTimeInterval(120)
        }
        return TripActivityAttributes.ContentState(
            phase: phase,
            busLineName: shuttleLeg?.line?.rawValue,
            boardingWindow: boardingWindow,
            arrivalEstimate: route?.arrivalTime ?? .now,
            nextClass: nextClass,
            stepsSoFar: stepsSoFar
        )
    }
}
