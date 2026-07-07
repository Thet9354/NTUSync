import ActivityKit
import WidgetKit
import SwiftUI

/// Live Activity rendering for an active campus trip. Every view is a pure
/// function of the pushed content state — countdowns render locally via
/// Text(timerInterval:), so ticking seconds never require a push.
struct TripLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            LockScreenTripView(context: context)
                .activityBackgroundTint(.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BusLineBadge(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownView(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    PhaseHeadline(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    NextClassRow(state: context.state, summary: context.attributes.routeSummary)
                }
            } compactLeading: {
                Image(systemName: phaseIcon(context.state.phase))
                    .foregroundStyle(.red)
            } compactTrailing: {
                CompactCountdown(state: context.state)
            } minimal: {
                Image(systemName: phaseIcon(context.state.phase))
                    .foregroundStyle(.red)
            }
        }
    }
}

private func phaseIcon(_ phase: TripPhase) -> String {
    switch phase {
    case .walkingToStop, .walkingToClass: "figure.walk"
    case .waitingForBus: "clock"
    case .riding: "bus.fill"
    case .arrived: "checkmark.circle.fill"
    }
}

private func phaseHeadline(_ state: TripActivityAttributes.ContentState) -> String {
    switch state.phase {
    case .walkingToStop: "Walk to the stop"
    case .waitingForBus: "\(state.busLineName ?? "Bus") arriving"
    case .riding: "On \(state.busLineName ?? "the shuttle")"
    case .walkingToClass: "Walk to destination"
    case .arrived: "Arrived"
    }
}

struct LockScreenTripView: View {
    let context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: phaseIcon(context.state.phase))
                Text(phaseHeadline(context.state))
                    .font(.headline)
                Spacer()
                CountdownView(state: context.state)
            }
            Text(context.attributes.routeSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let nextClass = context.state.nextClass {
                Text("\(nextClass.courseCode) · \(nextClass.venueShortName) · \(nextClass.startTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }
}

struct BusLineBadge: View {
    let state: TripActivityAttributes.ContentState

    var body: some View {
        VStack {
            Image(systemName: phaseIcon(state.phase))
                .font(.title3)
                .foregroundStyle(.red)
            if let line = state.busLineName {
                Text(line)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
    }
}

struct PhaseHeadline: View {
    let state: TripActivityAttributes.ContentState

    var body: some View {
        Text(phaseHeadline(state))
            .font(.headline)
            .lineLimit(1)
    }
}

/// Boarding countdown while heading to / waiting at the stop; otherwise the
/// arrival estimate. Rendered entirely in-process by the system.
struct CountdownView: View {
    let state: TripActivityAttributes.ContentState

    var body: some View {
        Group {
            if let window = state.boardingWindow, window.upperBound > .now {
                Text(timerInterval: window, countsDown: true)
            } else if state.arrivalEstimate > .now {
                Text(timerInterval: Date.now...state.arrivalEstimate, countsDown: true)
            } else {
                Text("—")
            }
        }
        .font(.title3.monospacedDigit())
        .frame(maxWidth: 60)
    }
}

struct CompactCountdown: View {
    let state: TripActivityAttributes.ContentState

    var body: some View {
        if let window = state.boardingWindow, window.upperBound > .now {
            Text(timerInterval: window, countsDown: true)
                .font(.caption.monospacedDigit())
                .frame(maxWidth: 44)
        } else {
            Image(systemName: "location.fill")
                .foregroundStyle(.red)
        }
    }
}

struct NextClassRow: View {
    let state: TripActivityAttributes.ContentState
    let summary: String

    var body: some View {
        HStack {
            if let nextClass = state.nextClass {
                Label("\(nextClass.courseCode) · \(nextClass.venueShortName)", systemImage: "graduationcap.fill")
                Spacer()
                Text(nextClass.startTime.formatted(date: .omitted, time: .shortened))
            } else {
                Label(summary, systemImage: "map")
                Spacer()
                if state.stepsSoFar > 0 {
                    Label("\(state.stepsSoFar)", systemImage: "shoeprints.fill")
                }
            }
        }
        .font(.caption)
    }
}
