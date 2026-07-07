import Foundation

nonisolated enum TripStateError: Error, Equatable {
    case illegalTransition(from: TripPhase, to: TripPhase)
}

/// Pure phase machine; the coordinator layers Live Activity pushes on top.
nonisolated struct TripStateMachine: Sendable, Equatable {
    private(set) var phase: TripPhase

    init(initial: TripPhase) {
        phase = initial
    }

    static let allowedTransitions: [TripPhase: Set<TripPhase>] = [
        .walkingToStop: [.waitingForBus, .walkingToClass],   // bail-out: skip the bus
        .waitingForBus: [.riding, .walkingToClass],          // missed it and walked
        .riding: [.walkingToClass],
        .walkingToClass: [.arrived],
        .arrived: [],
    ]

    mutating func advance(to next: TripPhase) throws(TripStateError) {
        guard Self.allowedTransitions[phase]?.contains(next) == true else {
            throw .illegalTransition(from: phase, to: next)
        }
        phase = next
    }
}
