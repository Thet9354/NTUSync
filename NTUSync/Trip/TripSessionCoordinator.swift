import Foundation
import os

/// Orchestrates one active trip: phase machine + Live Activity pushes.
/// Steps are coalesced into the next phase push, never pushed alone.
@MainActor
@Observable
final class TripSessionCoordinator {
    private let liveActivity: LiveActivityCoordinator

    private(set) var route: Route?
    private(set) var machine: TripStateMachine?
    private(set) var nextClass: ClassGlance?
    private var stepsSoFar = 0

    var phase: TripPhase? { machine?.phase }
    var isActive: Bool { machine != nil }

    init(liveActivity: LiveActivityCoordinator) {
        self.liveActivity = liveActivity
    }

    func start(route: Route, summary: String, nextClass: ClassGlance?) async throws {
        if isActive {
            await end()
        }
        let initialPhase: TripPhase = route.legs.contains { $0.kind == .shuttle }
            ? .walkingToStop
            : .walkingToClass
        self.route = route
        self.nextClass = nextClass
        self.stepsSoFar = 0
        let machine = TripStateMachine(initial: initialPhase)
        self.machine = machine

        let attributes = TripActivityAttributes(
            routeSummary: summary,
            destinationNodeID: route.destination?.rawValue ?? ""
        )
        do {
            try await liveActivity.begin(attributes: attributes, initialState: contentState(for: machine.phase))
        } catch LiveActivityError.activitiesDisabled {
            // Degraded mode: trip still runs in-app without a Live Activity.
            Logger.liveActivity.notice("trip running without live activity")
        }
    }

    func advance(to next: TripPhase) async throws(TripStateError) {
        guard var machine else { throw .illegalTransition(from: .arrived, to: next) }
        try machine.advance(to: next)
        self.machine = machine
        await liveActivity.push(contentState(for: machine.phase))
        if machine.phase == .arrived {
            await end()
        }
    }

    /// Fold pedometer progress into local state; surfaced on the next push.
    func recordSteps(_ total: Int) {
        stepsSoFar = total
    }

    func end() async {
        if let machine {
            await liveActivity.end(finalState: contentState(for: machine.phase))
        }
        route = nil
        machine = nil
        nextClass = nil
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
