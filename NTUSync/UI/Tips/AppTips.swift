import SwiftUI
import TipKit

/// Contextual first-run tips (TipKit) — the anti-overwhelm layer. Each tip is
/// anchored to the control it describes, appears once, is dismissible, and is
/// gated by rules so tips never stack. TipKit persists "seen" state on-device;
/// nothing here touches the network.

/// Anchored to the ＋ button on the Timetable. Only shows while the timetable
/// is empty — adding (or seeding) a course flips the parameter and retires it.
nonisolated struct AddCourseTip: Tip {
    @Parameter static var hasCourses: Bool = false

    var title: Text { Text("Add your courses here") }
    var message: Text? {
        Text("Build your timetable — odd/even teaching weeks and the recess week are handled for you.")
    }
    var image: Image? { Image(systemName: "calendar.badge.plus") }
    var rules: [Rule] {
        #Rule(Self.$hasCourses) { $0 == false }
    }
}

/// Anchored to the next-class hero card — which only exists once a course with
/// an upcoming session is in place, so no explicit rule is needed.
nonisolated struct RouteToClassTip: Tip {
    var title: Text { Text("Route straight to class") }
    var message: Text? {
        Text("NTUSync plans the fastest walk-and-shuttle route and can start live directions on your Lock Screen.")
    }
    var image: Image? { Image(systemName: "bus.fill") }
}

/// Anchored to the map ↔ compass toggle on the live trip header — visible only
/// during an active trip, so it naturally fires on the first trip.
nonisolated struct CompassTip: Tip {
    var title: Text { Text("Lost? Switch to compass") }
    var message: Text? {
        Text("A big arrow points at your next checkpoint — handy when you step outside disoriented.")
    }
    var image: Image? { Image(systemName: "location.north.circle.fill") }
}

/// Anchored to the Explore filter chips on first visit.
nonisolated struct ExploreTip: Tip {
    var title: Text { Text("Explore campus") }
    var message: Text? {
        Text("Study benches, food, and more near you — filter by what you need right now.")
    }
    var image: Image? { Image(systemName: "mappin.and.ellipse") }
}
