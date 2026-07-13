# NTUSync v2 — Feature Assessment & Implementation Plan

Assessment of the proposed improvements, feasibility on iOS 26, and a phased plan.
Guiding constraint: the app's identity is **offline-first**. Features that need the
network are fine as *user-initiated enhancements* that degrade gracefully — never as
dependencies for core flows.

---

## A. Routes

### A1. In-app route map with animated from→to rendering — **build now**
Render the computed route as a `MapPolyline` over MapKit (we already have per-node
coordinates for every leg), color-coded by leg kind (walk blue / shuttle red /
sheltered teal). On selection, animate the map camera along the route
(`MapCamera` keyframe animation) and draw the polyline with a trim animation.
Fully offline (Apple Maps tiles cache; the polyline itself is our data).
**Effort: small.**

### A2. Checkpoint imagery for first-time students — **use Apple Look Around, not photo shoots**
The trap: hand-captured photos for ~45 nodes are a content-maintenance burden and
bloat the bundle. The better native answer: **MapKit Look Around**
(`LookAroundPreview` / `MKLookAroundSceneRequest`) — Apple's own street-level
imagery, and **Singapore has full Look Around coverage including NTU's roads**.
Tapping any checkpoint in the route detail shows an interactive street-level view
of exactly that corner. Zero content to maintain.
Caveats: needs network (fallback: map snapshot of the node), and indoor nodes have
no coverage (fallback: our custom photo slot). Schema gets an optional
`checkpointPhoto` per node so you can add your own images for indoor checkpoints
during the field walk. **Effort: small–medium.**

### A3. Live trip screen with real-time user position — **build now**
A dedicated full-screen trip view: route polyline + `UserAnnotation()` (the blue
dot comes free from our existing `CLLocationManager` stream), camera-follow mode,
progress bar fed by the existing `RouteProgressEstimator`, phase timeline, and the
dead-reckoning "approximate" halo we already compute. This is the screen the
Dynamic Island taps into. Fully offline. **Effort: medium.**

### A4. Google-style AR "Live View" — **do not build for v1; ship the 80% alternative**
Honest assessment: Google's Live View needs city-scale visual localization.
Apple's equivalent (`ARGeoTrackingConfiguration`) is only available in a short
list of cities — **Singapore is not on it** — so true world-anchored AR arrows
are not implementable with public APIs today, and a hand-rolled version (ARKit +
compass) drifts badly and burns battery.
The 80% alternative that *is* feasible: **compass mode** — a large arrow that
rotates toward the next checkpoint using `CLLocationManager` heading, with
distance countdown ("Loop Red stop · 140 m ↗"). Works offline, costs almost
nothing, genuinely useful when emerging from a basement disoriented.
Plus A2's Look Around covers the "what does the turn look like" need.
**Effort: small (compass mode). Phase 3.**

---

## B. Timetable

### B1. Gap advisor — **build now; this is the app's "wow" feature**
We already have everything needed: today's sessions (SwiftData), venue→graph
joins, a routing engine, and a POI layer (benches + amenities from section D).
Detect gaps ≥ 30 min between consecutive same-day sessions and rank suggestions
by **actual walk time from the earlier class's venue** (RouteEngine, not
crow-flies): "90 min after SC2005 at SPMS → bench with power 2 min away ·
Canteen 2 lunch 6 min · LWN quiet floor 8 min". Suggestions are time-aware
(food at meal times, benches otherwise) and rain-aware (sheltered options first
on the rain-safe profile). Fully offline. **Effort: medium.**

### B2. Calendar & reminders integration — **build; two pieces**
1. **Apple Calendar export (EventKit):** one tap creates a dedicated "NTUSync"
   calendar and writes each session as individual events for the whole semester
   (individual occurrences, not RRULEs — that's how odd/even weeks and the recess
   week stay correct). Re-sync wipes and rewrites the NTUSync calendar only.
   **Google Calendar comes free**: if the user's Google account is added to iOS
   Calendar, exporting to it works identically — no Google API needed.
2. **"Leave now" alerts — use local notifications, not the Reminders app.**
   A notification scheduled at `classStart − routeTime − buffer`, with the route
   duration computed by our engine ("Leave for CZ2007 — 18 min via Loop Red").
   Reminders-app items can't do this timing math; notifications can, and they
   deep-link into the trip flow.
   Permissions needed: `NSCalendarsWriteOnlyAccessUsageDescription` (write-only
   calendar access is a softer prompt) + notification authorization.
   **Effort: medium.**

### B3. Additional recommendations (accepted ideas welcome)
- **Week grid view** — 13-week × weekday matrix so odd/even patterns are visible.
- **Conflict detection** — warn when a new session overlaps an existing one
  in the same teaching weeks (pure bitmask intersection — cheap).
- **ICS share export** — share the semester as a `.ics` file (works with any
  calendar app, no permissions at all).
- **Exam mode** — separate one-off events (date, venue, seat no.) with countdown.

---

## C. Benches

### C1. Photos on benches — **build**
`PhotosPicker` on the detail sheet, stored as `@Attribute(.externalStorage) Data`
on `StudyBench` (SwiftData keeps blobs out of the main store file). Thumbnail in
the detail sheet and a larger tappable preview. Camera capture too, since you'll
be standing at the bench when adding it. Offline. **Effort: small.**
(Schema change → SchemaV2 + migration stage — the versioning we set up pays off here.)

### C2. Navigate-to-bench button — **build now; trivial**
"Take me there" on the bench sheet: current location → nearest node → route →
straight into the existing trip flow with Live Activity. **Effort: tiny.**

### C3. Populating real bench/power data — **three-layer strategy**
1. **Curated seed expansion (now):** grow the seed to ~30 well-known spots (LWN
   floors, Hive pods by level, South Spine clusters, ADM lounge, NBS lounge,
   canteen off-peak tables, EEE/SCSE study corners) marked "community-sourced —
   verify", refined during your field walk. I can generate this list; you
   ground-truth it.
2. **In-app crowdsourcing (already shipped):** the tap-to-add flow is exactly
   how the DB grows organically on each device.
3. **Shared community layer (Phase 3):** cross-user sharing needs a backend.
   The zero-server option is **CloudKit public database** — free at this scale,
   no server to run, Apple-hosted. This is also the only honest way to do
   "is this spot currently occupied": lightweight check-ins with a 30-min TTL.
   Real-time occupancy without user check-ins would require campus sensors —
   not feasible. **Needs the paid membership; fits your timeline.**

---

## D. The all-in-one campus layer (food / supper / supermarket / recreation)

### D1. Amenity POI system — **build the foundation now**
New model + seed dataset: `Amenity { name, category, graphNodeID, coordinate,
openingHours, note }` with categories: `food`, `supper`, `cafe`, `supermarket`,
`alcohol`, `gym`, `recreation`, `printing`, `atm`, `clinic`. UI: a category
filter chip row on the map + a "Nearest…" query answered by **walk time from
your location or your hall** (RouteEngine), with open/closed state from
opening hours ("Prime Supermarket · North Spine · 6 min walk · open till 11pm").

Honest data notes for your examples:
- Supper/food: canteens with extended hours, North Spine food court, Extension
  cafes — good coverage on campus.
- Alcohol: on-campus options are thin (supermarkets sell beer; Nanyang Executive
  Centre has a lounge) — the app should say so honestly and can list the nearest
  off-campus options (Boon Lay/Jurong Point) as "off campus" entries.
- "Is it being used / crowded": same answer as C3 — static "typical peak hours"
  now, CloudKit check-ins in Phase 3. No API exists for live campus crowd data.

### D2. "My hall" personalization — **build with D1**
A `homeNodeID` in UserSettings ("I live in Hall 6") powers a personal shelf:
nearest food/supper/bench/gym from *your hall*, and "route home" from anywhere
in one tap.

---

## E. UI/UX modernization — **a concrete pass, not vague polish**

- **Adopt the iOS 26 design language deliberately**: glass toolbars/tab bar come
  free; add `.glassEffect` accents on hero cards and the trip screen.
- **Hero cards**: next-class and active-trip as gradient cards (course
  `colorSeed` already exists in the schema — finally use it for per-course color
  identity) instead of plain list rows.
- **Motion**: spring transitions between planner → trip screen
  (`matchedGeometryEffect`), animated route polyline draw-in, `symbolEffect
  (.pulse)` on the live bus icon, `contentTransition(.numericText())` on
  countdowns and ETAs so numbers roll instead of snapping.
- **Haptics**: `sensoryFeedback` on phase transitions and route-found.
- **Map as the visual anchor**: planner results get the A1 map preview instead
  of text-only legs.
- Applied as part of Phase 1 (it rides along with A1/A3 screens).

---

## Phasing

| Phase | Contents | Needs |
|---|---|---|
| **1 — now** | A1 route map + animation · A3 live trip screen · C2 navigate-to-bench · D1 amenity foundation + seed · B1 gap advisor · C3 seed expansion · E design pass | Nothing new — offline, no permissions |
| **2 — before launch** | B2 calendar export + leave-now notifications · A2 Look Around checkpoints · C1 bench photos (SchemaV2) · D2 my-hall shelf · B3 conflict detection + ICS | Calendar/notification permission strings |
| **3 — post-launch** | CloudKit community benches + occupancy check-ins · A4 compass mode · exam mode · week grid | Paid membership (CloudKit), field data |

**Decision points:**
1. Phase 1 scope OK to start?
2. A2: Look Around as primary checkpoint imagery (my recommendation) vs. hand-shot photos?
3. B2: local "leave now" notifications (my recommendation) vs. Reminders-app items?
