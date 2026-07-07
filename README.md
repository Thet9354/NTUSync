# NTUSync

**Offline campus transit optimizer and academic scheduler for NTU Singapore** — iOS 26+, SwiftUI, Swift 6 strict concurrency. All routing and schedule data lives on-device; the app makes zero network requests.

## What it does

- **Campus routing** — A* pathfinding over a hand-modelled NTU campus graph (buildings, walkways, link bridges, stairs, shuttle stops), with time-dependent Campus Loop shuttle costs and four travel profiles: *Fastest*, *Rain-safe* (weights sheltered walkways for monsoon season), *Step-free*, and *Min-walk*.
- **Live Activities** — active trips render on the Lock Screen and Dynamic Island with a bus-boarding countdown. Countdowns tick client-side (`Text(timerInterval:)`); a full trip costs ≤ 6 ActivityKit pushes.
- **Trip autopilot** — GPS fixes advance the trip through its phases (walk → wait → ride → walk → arrived) automatically; in GPS-denied basements the app falls back to pedometer dead reckoning constrained to the route's geometry.
- **Timetable** — courses and sessions stored fully offline in SwiftData, with NTU's teaching-week structure (13 weeks, recess after week 7, odd/even-week sessions) encoded as a 13-bit mask.
- **Study benches** — a curated campus map of study spots with power/shelter metadata.

## Architecture

```
SwiftUI ──▶ TripSessionCoordinator (@MainActor)  ──▶ LiveActivityCoordinator ──▶ NTUSyncWidgets.appex
   │              │  TripAutopilot (pure)                 (ActivityKit txn mgr)      (Dynamic Island)
   │              │  RouteProgressEstimator (pure)
   │              ▼
   │        RouteEngine (actor) ── A* over CampusGraph (immutable, Sendable)
   │              ▲
   └── SwiftData (SchemaV1, versioned) ── graphNodeID string joins ──┘
```

Key decisions (full rationale in [Docs/TECHNICAL_DESIGN_SPECIFICATION.md](Docs/TECHNICAL_DESIGN_SPECIFICATION.md)):

- The campus graph is an **immutable value type** bundled as JSON — never in the database — so the A* hot loop cannot fault managed objects and the whole routing layer is thread-safe by construction.
- Search states are **(node, shuttle line)** pairs, so boarding waits and transfers between Loop Red/Blue are costed correctly.
- Live Activity state is pushed **only on plan transitions**; ticking time is rendered by the system.
- Dead reckoning is **1-D along the route** (the graph is the map-matching prior), with confidence decay and a snap-vs-replan rule on GPS reacquisition.

## Building

Open `NTUSync.xcodeproj` in Xcode 26+ and run the `NTUSync` scheme. No package dependencies; no configuration needed.

```sh
xcodebuild -scheme NTUSync -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The test suite doubles as the data contract: graph integrity (edge lengths vs haversine, foot-network connectivity, timetable coverage), an A*≡Dijkstra equivalence property test, autopilot transition rules, the ActivityKit push budget, and crash-recovery snapshot rebinding.

## Campus data

`NTUSync/Resources/CampusGraph.json` is generated — do not edit by hand. Edit the node/edge tables in [Tools/generate_campus_graph.py](Tools/generate_campus_graph.py) and re-run it; the generator derives edge lengths from coordinates so the validation tests stay green. Shuttle headways live in `NTUSync/Resources/ShuttleTimetable.json` (`validUntil` marks staleness).

## Status

Core feature-complete and unit-tested. Pre-release checklist: on-campus field validation of graph coordinates and shuttle headways, and a battery pass (target < 2%/hr during active trips).
