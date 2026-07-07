# NTUSync — Technical Design Specification & Implementation Plan

**Version:** 1.0 · **Date:** 2026-07-07 · **Target:** iOS 26+, Swift 6 strict concurrency, Xcode 26
**Bundle IDs:** `com.thetpine.workspace.NTUSync` (app) · `com.thetpine.workspace.NTUSync.Widgets` (extension, to be created)

---

## 0. Architectural Summary

NTUSync is a fully-offline campus transit optimizer and academic scheduler for NTU Singapore. Four subsystems, each isolated behind a protocol boundary:

```
┌─────────────────────────────────────────────────────────────────┐
│                        SwiftUI App Layer                         │
│   RoutePlannerView · TimetableView · LiveTripView · BenchMap     │
└──────────┬───────────────┬───────────────┬──────────────────────┘
           │ @Observable   │ @Query        │ async calls
┌──────────▼─────┐ ┌───────▼───────┐ ┌─────▼──────────────────────┐
│ TripSession    │ │ SwiftData     │ │ RouteEngine (actor)        │
│ Coordinator    │ │ ModelContainer│ │  A* over CampusGraph       │
│ (@MainActor)   │ │ (offline)     │ │  (immutable, Sendable)     │
└──────┬─────────┘ └───────────────┘ └────────────────────────────┘
       │ start/update/end
┌──────▼──────────────────┐   ┌──────────────────────────────────┐
│ LiveActivityCoordinator │──▶│ NTUSyncWidgets extension          │
│ (ActivityKit txn mgr)   │   │ Dynamic Island + Lock Screen      │
└──────┬──────────────────┘   └──────────────────────────────────┘
┌──────▼──────────────────────────────────────────────────────────┐
│ SensorFusion: CLLocationManager + CMPedometer + graph snapping   │
└──────────────────────────────────────────────────────────────────┘
```

Load-bearing decisions (each justified in its section):

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Graph is an **immutable `Sendable` struct** bundled as JSON, *not* stored in SwiftData | Pathfinding hot loop must not fault managed objects; static topology needs no persistence |
| D2 | Routing runs in a **dedicated `actor RouteEngine`** with time-dependent A* | Thread safety by isolation, not locks; shuttle waits are time-of-day functions |
| D3 | Live Activity countdowns rendered with **`Text(timerInterval:)`**, state pushed only on *plan changes* | Eliminates per-second updates; respects ActivityKit update budget and battery |
| D4 | Indoor dead zones handled by **pedometer dead-reckoning snapped to graph edges** | GPS is unavailable in NTU basements/tunnels; the graph itself is the map-matching prior |
| D5 | SwiftData holds **user & schedule data only**, referencing graph nodes by stable string IDs | Clean separation of mutable user state from immutable topology |

---

## 1. Topological Graph Theory Pathfinding Core

### 1.1 Domain model of the NTU network

NTU's campus decomposes into a directed weighted multigraph `G = (V, E)`:

- **Nodes (`V`, ~350 expected):** buildings (Hive/LHN, LWN Library, SPMS, NIE, ADM, halls 1–21, canteens), shuttle stops (Campus Loop Red/Blue, Campus Rider, Campus Weekend Rider stops), and *junction nodes* (path intersections, staircase heads, linkbridge ends). Junction nodes are essential — without them, walking shortcuts through the Hive spine or the North Spine covered walkway cannot be expressed.
- **Edges (`E`):** typed, directed (staircases and one-way shuttle loops are asymmetric):

```swift
enum EdgeKind: String, Codable, Sendable {
    case walk            // open-air footpath
    case shelteredWalk   // covered walkway / linkbridge (rain-safe)
    case stairs          // has elevationDelta; penalized when accessibility mode on
    case shuttle         // carries line: ShuttleLine, boarding requires wait cost
    case indoor          // corridor inside a building (GPS-denied by definition)
}
```

A multigraph is required: two stops on both Loop Red and Loop Blue have *two* distinct shuttle edges plus a walking edge between them.

### 1.2 Core types

```swift
struct NodeID: Hashable, Codable, Sendable, RawRepresentable { let rawValue: String } // e.g. "stop.loop-red.hall-6"

struct GraphNode: Codable, Sendable {
    let id: NodeID
    let coordinate: CLLocationCoordinate2D   // wrapped in a Sendable Codable shim
    let elevation: Double                    // metres AMSL; NTU is hilly (Nanyang Hill ~50 m)
    let isIndoor: Bool                       // drives GPS-denial handling (§5.1)
    let displayName: String?
}

struct GraphEdge: Codable, Sendable {
    let from: NodeID, to: NodeID
    let kind: EdgeKind
    let lengthMetres: Double
    let elevationDelta: Double               // signed; uphill penalized
    let line: ShuttleLine?                   // nil unless kind == .shuttle
}

struct CampusGraph: Sendable {
    let nodes: [NodeID: GraphNode]
    let adjacency: [NodeID: [GraphEdge]]     // out-edges, contiguous per node
}
```

`CampusGraph` is built once at launch from `CampusGraph.json` in the bundle, validated (see §1.6), and shared freely across actors because it is a deeply immutable value — **this is what makes the whole routing layer trivially thread-safe** (D1).

### 1.3 Travel-cost matrices (customizable weight profiles)

Cost is not distance; it is a user-profile-weighted composite evaluated per edge:

```
cost(e, t, p) = time(e, t) · (1 + p.rainAversion·exposure(e) + p.slopeAversion·max(0, Δh/len))
time(e, t)    = len/v_walk                     for walk-kind edges (v_walk from profile, default 1.35 m/s)
              = expectedWait(line, stop, t) + rideTime(e)   for shuttle edges
```

`expectedWait` is **time-dependent**: computed from the bundled shuttle timetable (headway table per line per period — peak ~5 min, off-peak ~15 min, weekend rider schedule). Between timetable entries, wait defaults to `headway/2` (uniform arrival assumption). This makes the graph a *time-expanded* problem solved lazily: A* labels carry arrival time `t`, and edge relaxation evaluates `cost(e, t_label, profile)`. Because waits are FIFO and non-negative, the problem retains the non-negative-weights invariant Dijkstra/A* require (formally: the arrival function is non-decreasing — the "FIFO network" condition — so label-setting search remains correct).

`TravelProfile` presets: `fastest`, `rainSafe` (monsoon season — heavily weights `shelteredWalk`), `accessible` (stairs → ∞), `lazy` (prefer shuttle even when walking is marginally faster).

### 1.4 The routing actor

```swift
actor RouteEngine {
    private let graph: CampusGraph
    private let timetable: ShuttleTimetable
    private var cache: [RouteQuery: Route]           // LRU, capacity 64

    func route(_ query: RouteQuery) throws(RoutingError) -> Route
    func nearestNode(to coord: CLLocationCoordinate2D, filter: (GraphNode) -> Bool) -> NodeID
}
```

- **Thread safety by isolation:** all mutable state (the memo cache) lives inside the actor. Callers `await` from any context; Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`) proves absence of data races at compile time. No locks, no queues.
- **Algorithm: A\*** with admissible heuristic `h(n) = haversine(n, goal) / v_max`, where `v_max = max(v_walk, v_shuttle ≈ 8.3 m/s)`. Dividing by the *maximum* achievable speed keeps `h` a lower bound on remaining time ⇒ admissible and consistent ⇒ first settlement of the goal is optimal.
- **Priority queue:** `Heap<SearchLabel>` from `swift-collections` (add as SPM dependency). Decrease-key is emulated by lazy deletion (push duplicate, skip settled nodes on pop) — simpler and empirically faster than indexed heaps at this graph size.
- **Complexity:** `O((V + E) log V)` ≈ 350 nodes / ~1,200 edges → sub-millisecond per query on any A-series chip. The LRU cache exists for the Live Activity re-plan loop (§2.4), not for raw speed.
- **Reentrancy note:** actor methods are synchronous internally (no suspension points inside the search), so actor reentrancy cannot interleave two searches mid-flight and corrupt the cache.

### 1.5 Route output

```swift
struct Route: Sendable, Hashable {
    let legs: [Leg]                 // Leg = (edge sequence, kind, boardingTime?, line?)
    let departureTime: Date
    let arrivalTime: Date
    let totalWalkMetres: Double
    let exposedMetres: Double       // rain-exposed distance, surfaced in UI
}
```

Legs coalesce consecutive same-kind edges so the UI renders "Walk 4 min → Loop Blue 3 stops → Walk 1 min", and each shuttle leg carries the concrete boarding time used to drive the Live Activity countdown.

### 1.6 Graph integrity verification (build-time, not runtime)

A unit test suite (`CampusGraphValidationTests`) is the *contract* on the data file:

1. Every edge endpoint exists in `nodes`.
2. The walk-subgraph is strongly connected (BFS from an arbitrary node reaches all non-shuttle-only nodes) — catches "island" data-entry errors.
3. Every `shuttle` edge's `line` matches a timetable entry; every stop on a line has a boarding node.
4. Haversine(from, to) ≤ `lengthMetres` ≤ 3 × haversine (sanity band; catches swapped coordinates).
5. Elevation deltas along any cycle sum to ≈ 0 (± 2 m tolerance).

---

## 2. ActivityKit & Dynamic Island Synchronization Layer

### 2.1 Targets & attributes

New target: **`NTUSyncWidgets`** (Widget Extension, "Include Live Activity" checked). Shared framework-less code via a shared file group (`Shared/`) compiled into both targets — attributes types **must** be byte-identical across app and extension or decoding fails silently.

```swift
struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: TripPhase                    // .walkingToStop, .waitingForBus, .riding, .walkingToClass
        var busLine: String?                    // "Loop Red"
        var boardingWindow: ClosedRange<Date>?  // drives Text(timerInterval:) countdown
        var arrivalEstimate: Date
        var nextClass: ClassGlance?             // code, venue short-name, start time
        var stepsSoFar: Int
    }
    let routeSummary: String                    // immutable per-activity: "Hall 6 → SPMS LT1"
    let destinationNodeID: String
}
```

### 2.2 Transaction manager

`LiveActivityCoordinator` is the *only* type in the app allowed to touch ActivityKit — a structured transaction manager enforcing a legal state machine:

```swift
@MainActor final class LiveActivityCoordinator {
    private var activity: Activity<TripActivityAttributes>?
    private var lastPushedState: TripActivityAttributes.ContentState?

    func begin(trip: Trip) async throws(LiveActivityError)   // idempotent; ends stale activity first
    func push(_ state: ContentState, staleAfter: TimeInterval) async
    func end(dismissal: ActivityUIDismissalPolicy) async
}
```

Transaction rules (each enforced in code, each logged):

1. **Single-activity invariant:** at most one trip activity. `begin` ends any orphan (`Activity<TripActivityAttributes>.activities`) left over from a crash before requesting anew.
2. **Enablement gate:** check `ActivityAuthorizationInfo().areActivitiesEnabled` before `request`, and observe `activityEnablementUpdates` for mid-trip revocation → degrade to in-app banner, log at `.notice`.
3. **De-duplication:** `push` no-ops when `state == lastPushedState` — the countdown itself never requires a push (D3, see §2.4).
4. **Stale dating:** every update sets `staleDate` = boarding time + 90 s, so a suspended app yields a visibly-stale (dimmed) activity rather than a lying countdown.
5. **Relevance:** `relevanceScore` = 100 while `.waitingForBus` (contested Dynamic Island slot goes to us), 50 otherwise.

### 2.3 Dynamic Island layout panes

```swift
ActivityConfiguration(for: TripActivityAttributes.self) { context in
    LockScreenTripView(context)                        // Lock Screen / StandBy banner
} dynamicIsland: { context in
    DynamicIsland {
        DynamicIslandExpandedRegion(.leading)  { BusLineBadge(context) }
        DynamicIslandExpandedRegion(.trailing) { CountdownRing(context) }   // Text(timerInterval:)
        DynamicIslandExpandedRegion(.center)   { PhaseHeadline(context) }
        DynamicIslandExpandedRegion(.bottom)   { NextClassRow(context) }    // "CZ2007 · SPMS LT1 · 10:30"
    } compactLeading: { Image(systemName: "bus.fill") }
      compactTrailing: { Text(timerInterval: context.state.boardingWindow ?? .now....now, countsDown: true).monospacedDigit() }
      minimal: { CountdownGlyph(context) }
}
```

Constraints honored: expanded height ≤ 160 pt, no animations besides system text transitions, all views pure functions of `context` (extension executes headless renders).

### 2.4 Update cadence design (the critical budget decision)

ActivityKit throttles/penalizes chatty local updates, and every push costs a Springboard render. The design pushes state **only on discrete plan transitions**:

| Trigger | Push? | Mechanism |
|---|---|---|
| Seconds ticking down to bus | **No** | `Text(timerInterval:)` renders client-side in the extension |
| Phase change (arrived at stop, boarded) | Yes | SensorFusion geofence/edge-snap event |
| Re-route (missed bus → next headway) | Yes | `RouteEngine.route` re-query, then push |
| Step count | Coalesced | Folded into the next phase push only (never pushed alone) |

Expected pushes per trip: **3–6 total**, versus ~600 for naive per-second updates.
CoreMotion cannot run inside the widget extension — `CMPedometer` lives in the app process; the extension only renders whatever `stepsSoFar` was last pushed.

---

## 3. SwiftData Offline Relational Schema

### 3.1 Entity-relationship design

```
Course 1 ──── * ClassSession * ──── 1 Venue
                                        │ nodeID: String  ──▶ CampusGraph (by ID, not relation)
StudyBench (standalone)                 │
UserSettings (singleton row)     ShuttleTimetable rows are NOT SwiftData — bundled immutable JSON
```

```swift
@Model final class Course {
    #Unique<Course>([\.code])
    var code: String            // "SC2005"
    var title: String
    var colorSeed: Int          // deterministic UI color
    @Relationship(deleteRule: .cascade, inverse: \ClassSession.course)
    var sessions: [ClassSession] = []
}

@Model final class ClassSession {
    var kind: SessionKind       // lecture / tutorial / lab (String-backed enum)
    var dayOfWeek: Int          // 1...7, ISO
    var startMinutes: Int       // minutes from midnight — avoids Date/timezone traps entirely
    var durationMinutes: Int
    var teachingWeeksMask: Int  // bitmask weeks 1–13; bit i-1 == week i active (handles odd/even-week NTU labs)
    var venue: Venue?
    var course: Course?
}

@Model final class Venue {
    #Unique<Venue>([\.shortName])
    #Index<Venue>([\.shortName])
    var shortName: String       // "SPMS-LT1"
    var latitude: Double
    var longitude: Double
    var graphNodeID: String     // stable join into CampusGraph — D5
    var isIndoor: Bool
}

@Model final class StudyBench {
    var latitude: Double
    var longitude: Double
    var graphNodeID: String
    var hasPower: Bool
    var isSheltered: Bool
    var userRating: Int?
    var note: String?
}
```

Design rules:

- **`startMinutes: Int`, not `Date`:** recurrence math ("next occurrence of this session in teaching week `w`") becomes pure integer arithmetic against a semester-start anchor stored in `UserSettings`; immune to DST-nonexistent-but-timezone-shifted travel bugs.
- **`teachingWeeksMask`:** NTU tutorials/labs frequently run odd or even weeks only; a 13-bit mask encodes any pattern (odd = `0b1010101010101`).
- **Graph joined by `graphNodeID` string, not relationship (D5):** SwiftData faulting inside the A* loop would serialize the search behind the model actor and thrash; the graph stays a value type, the DB stores only the foreign key.
- **Container config:** `ModelConfiguration(isStoredInMemoryOnly: false, allowsSave: true)`, no CloudKit — the requirement is strictly offline. All context access via `@ModelActor` (`PersistenceStore`) for background writes; SwiftUI reads via `@Query` on the main context.

### 3.2 Seeding & migration

- First-launch seed: `SeedImporter` (a `@ModelActor`) reads `Venues.json` + `StudyBenches.json` from bundle inside one transaction; a `UserSettings.seedVersion` stamp makes it idempotent and re-runnable when bundle data updates.
- Schema evolution: `SchemaV1: VersionedSchema` from day one, `NTUSyncMigrationPlan: SchemaMigrationPlan` with an empty stage list — paying ~20 lines now buys lightweight migrations forever and avoids the "unversioned → versioned" trap.

---

## 4. Multi-Week Engineering Execution Roadmap

Logging contract used by every milestone — one subsystem, fixed categories:

```swift
extension Logger {
    static let routing     = Logger(subsystem: "com.thetpine.workspace.NTUSync", category: "routing")
    static let liveActivity = Logger(subsystem: "com.thetpine.workspace.NTUSync", category: "liveactivity")
    static let persistence = Logger(subsystem: "com.thetpine.workspace.NTUSync", category: "persistence")
    static let location    = Logger(subsystem: "com.thetpine.workspace.NTUSync", category: "location")
    static let motion      = Logger(subsystem: "com.thetpine.workspace.NTUSync", category: "motion")
}
```

Boundary rule: log at **every** subsystem boundary crossing (query in / route out, push attempted / push result, seed begin / count / end), `.debug` for payloads (redacted by default via `\(x, privacy: .private)` for coordinates — location is personal data), `.error` only for actionable failures.

| Week | Milestone | Exact verification logic | API intersections |
|---|---|---|---|
| **1** | Project hygiene: `SWIFT_STRICT_CONCURRENCY=complete`, Swift 6 language mode, SPM `swift-collections`, Logger scaffold, `Shared/` group, CI-able `xcodebuild test` scheme | `xcodebuild -scheme NTUSync test` green on empty test target; zero concurrency warnings | Foundation, os |
| **2** | `CampusGraph` types + JSON codec + hand-built 25-node pilot graph (North Spine area) | `CampusGraphValidationTests` §1.6 all pass; decode round-trip equality test | Foundation, CoreLocation (types only) |
| **3** | `RouteEngine` actor: Dijkstra first, then A*; heap via lazy deletion | Property tests: (a) A* cost == Dijkstra cost on 500 random node pairs; (b) route is a connected edge chain; (c) heuristic admissibility asserted along every settled label (`h ≤ settledCost(goal) − g`) | swift-collections.Heap |
| **4** | Time-dependent shuttle costs + `TravelProfile` presets; full ~350-node graph data entry | Golden-file tests: 12 curated real queries (e.g. Hall 6 → LWN at 08:20 peak) with hand-verified expected legs; monotonicity test: later departure never yields earlier arrival (FIFO property) | — |
| **5** | SwiftData schema V1, `PersistenceStore` model actor, seed importer, timetable entry UI | In-memory-container unit tests: cascade delete Course → sessions vanish; `teachingWeeksMask` next-occurrence math against 26 fixture cases incl. recess week; seed idempotency (run twice, count stable) | SwiftData, SwiftUI @Query |
| **6** | Route planner UI + timetable UI wired to engine ("route me to my next class") | UI test: seeded fixture → tap next-class chip → leg list matches golden route; `Logger.routing` signposts show query < 5 ms (measure with `XCTMetric`/os_signpost) | SwiftUI, os.signpost |
| **7** | Widget extension target, `TripActivityAttributes`, static Lock Screen + Dynamic Island layouts with mocked state | Manual matrix on device: compact/minimal/expanded render; stale-date dimming observed by setting staleDate = now+10 s; snapshot tests of lock-screen view | ActivityKit, WidgetKit |
| **8** | `LiveActivityCoordinator` transaction manager + `TripSessionCoordinator` phase machine (manual phase advance buttons first — no sensors yet) | State-machine unit tests: illegal transitions throw; orphan-activity cleanup test (begin → kill → begin finds & ends orphan); assert ≤ 6 pushes across a simulated full trip (counter in test double) | ActivityKit |
| **9** | SensorFusion: `CLLocationManager` (when-in-use), geofence-driven phase transitions, `CMPedometer` steps, indoor dead-reckoning fallback (§5.1) | Field test protocol on campus: 3 scripted trips with `Logger.location` streamed via Console.app; assert phase transitions within 30 m/20 s of ground truth; basement test at LWN B1 confirms fallback engages (log marker `gps.denied → dr.engaged`) | CoreLocation, CoreMotion |
| **10** | Battery/QoS pass (§5.2), accessibility audit, error-path hardening, TestFlight, README + demo video for scholarship/internship portfolio | 2-hour tracked-trip battery delta < 4% on device (Xcode Energy gauge + MetricKit `MXMetricPayload` cross-check); zero `.error` logs across 20 trips; Instruments Time Profiler: no main-thread work > 8 ms | MetricKit, Instruments |

Weeks 2–4 are UI-free on purpose: the routing core is verified as a pure library before any pixel exists, which is what makes weeks 6–9 debuggable.

---

## 5. System Failure Modes & Fail-Safe Mitigations

### 5.1 F-1: GPS-denied zones (deep basements, tunnels, Hive interior)

**Failure signature:** `CLLocation.horizontalAccuracy` degrades (> 50 m) or updates stop entirely; naive apps show the user teleporting or frozen.

**Mitigation — graph-constrained pedestrian dead reckoning:**
1. **Detection:** accuracy > 50 m for 10 s, *or* the snapped node has `isIndoor == true`. Log `location: gps.denied`.
2. **Fallback estimator:** switch position source to `CMPedometer` distance deltas. Crucially, position is advanced **along the active route's edge chain** (1-D arc-length coordinate), not in free 2-D — the graph is the map-matching prior, collapsing drift to a single dimension. Heading is not trusted indoors (steel structure corrupts the magnetometer); route topology substitutes for heading.
3. **Confidence decay:** estimated error grows 8% of distance walked; UI shows a widening "approximate" halo instead of a confident dot; Live Activity keeps countdowns (time-based, unaffected) but suppresses "arriving now" phase flips until confidence recovers.
4. **Re-acquisition:** first fix with accuracy < 30 m snaps back; if the fix disagrees with the estimate by > 75 m, re-run `RouteEngine.route` from the fix (user likely deviated) rather than force-snapping. Log `location: dr.reconciled(driftMetres:)`.

### 5.2 F-2: Battery drain during active tracking

**Budget: < 2%/hour during an active trip.** Levers, in order of impact:

| Lever | Policy |
|---|---|
| Location accuracy tiering | `.hundredMetres` + `distanceFilter=25` while walking far from decision points; escalate to `.best` only within 120 m of a stop/turn geofence; `.reduced` when no trip is active (benches map only) |
| Geofences over polling | Phase transitions use `CLCircularRegion`/`CLMonitor` monitoring (hardware-assisted, near-zero cost) instead of continuous comparison loops |
| No background location entitlement in v1 | Trips are foreground + Live Activity; the Live Activity survives lock, so continuous background location is unnecessary — the single biggest battery win |
| ActivityKit push discipline | §2.4: 3–6 pushes/trip, countdowns rendered by the system |
| Verification | Week-10 MetricKit + Energy-gauge protocol; regression gate: any change to SensorFusion re-runs the 2-hour test |

### 5.3 F-3: Shuttle timetable drift (real service ≠ bundled schedule)

Bundled headways go stale (exam-period schedules, route changes). Mitigations: expected-wait model already uses `headway/2` uncertainty rather than exact times; boarding windows displayed as ranges, never exact minutes; missed-window detection (user still at stop 2 min past window per geofence dwell) triggers silent re-plan onto next headway + one `.notice` log; data file carries `validUntil` — past it, UI shows an unobtrusive "schedule may be outdated" chip.

### 5.4 F-4: ActivityKit denial / revocation / process death

Covered by transaction rules §2.2: enablement gate with in-app banner fallback; orphan-activity sweep on `begin` recovers from crashes; `staleDate` guarantees a killed app never shows a live-looking lie. Additionally `TripSessionCoordinator` persists a lightweight `ActiveTripSnapshot` (JSON in Application Support) so app relaunch can rebind to the surviving `Activity` instance by ID and resume pushing.

### 5.5 F-5: SwiftData migration or seed corruption

All writes behind `PersistenceStore` model actor ⇒ no cross-context write races. Migration failure (container init throws): log `.fault`, move store aside (`.store` → `.store.corrupt-<timestamp>`), rebuild from seed — user loses ratings/notes but the app never bricks; timetable re-entry is prompted. Seed importer is transactional and idempotent (§3.2), so a mid-seed kill re-runs cleanly.

### 5.6 F-6: Concurrency regressions

Swift 6 strict concurrency is the primary defense (compile-time). Residual risks: actor *reentrancy* (mitigated in §1.4 — no awaits inside the search critical section) and main-thread stalls (RouteEngine keeps heavy work off `@MainActor` by construction; week-10 Instruments gate enforces < 8 ms main-thread slices).

---

## 6. Non-Goals (v1)

Explicitly out of scope, to protect the roadmap: real-time bus GPS ingestion (no public NTU feed; would break the offline guarantee), CloudKit sync, indoor floor-level routing (per-floor graphs are a v2 extension of `EdgeKind.indoor`), Android, and push-token remote Live Activity updates (local-only pushes suffice for an on-device planner).
