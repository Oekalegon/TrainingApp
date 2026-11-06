# Apple Watch app: scoping

Status: draft for exploration (2026-11-06). Nothing is decided yet; open questions are in §9. Covers TrainingApp (a new watchOS target) and the TrainingKit changes it needs. Todo IDs will be `WATCH-xxx` in `TODO.md` once the scope is agreed. Replaces the one-line "watchOS companion" item in `TODO.md`.

## 1. Why

Two problems, one app.

1. **Zones disagree.** The Watch gets a planned workout through WorkoutKit (`WatchScheduleSync`). Each step's zone becomes a bpm range for the alert, but Apple's Workout app shows and stores its *own* zones, computed from Health's maximum heart rate and its own pace zones. After a run the athlete sees one set of zones on the Watch and another in TrainingApp. TrainingApp's zones carry the athlete's settings (maximum, resting, lactate threshold, method, dated history) and the load, time in zone and plan guardrails are built on them.
2. **The Workout app's data views are fixed.** The athlete cannot choose what the Watch shows during a step (zone position, step progress, pace against the step's target, a map). TrainingApp knows what the step is for, so it can show more.

The Watch app makes the athlete's zones the zones on the wrist, and shows the data that suits the step.

## 2. Goals and non-goals

Goals:

- Record a workout on the Watch whose live zones, alerts and stored zone data come from TrainingApp's athlete settings.
- Run a planned workout step by step, with TrainingApp's resolved targets (heart-rate zone, pace range, zone fraction once MVP5-148 lands).
- Saved workouts are ordinary `HKWorkout`s, so the existing import, plan link, load and time in zone keep working unchanged.
- Data views built for training: current zone with position inside it, step progress, pace against the target, a live map.

Non-goals (for now):

- Replacing Apple's Workout app. It stays; the athlete chooses which to start.
- Sports other than running (the plan assistant is running only, MVP5).
- Plan editing, plan generation or history browsing on the Watch.
- A standalone Watch app without the iPhone ever having run. The iPhone sets the athlete up first.

## 3. What exists today

| Piece | Where | State |
|---|---|---|
| Planned workouts on the Watch | `WatchScheduleSync`, `WorkoutKitBridge` (TrainingKit) | Done: 7-day window of `CustomWorkout`s, HR range or pace alerts |
| Workout import and plan link | `HealthKitWorkoutObserver`, `WorkoutBackgroundImport` | Done: by `WorkoutPlan` id, then same-day heuristic (`PlanReconciler`) |
| Per-step data | `HKWorkoutActivity` per step, metadata `WOIntervalStepKeyPath` | Done (MVP2-146 spike, 2026-10-11) |
| Athlete zones | `HeartRateZoneModel`, dated history | Done; pace zones MVP8 |
| HealthKit access | read only: workouts, heart rate, resting HR, sex, birth date | A recording app also needs **write** access |
| watchOS in TrainingKit | `Package.swift` declares `.watchOS(.v26)` | Declared; whether each target builds for watchOS is unchecked (see §9) |
| watchOS in TrainingAppKit | `Package.swift` declares iOS and macOS only | Needs `.watchOS` |
| Route import and map | MVP4-100 (not started) | The iPhone map needs `HKWorkoutRoute` import first |

## 4. Architecture

```
iPhone                                         Apple Watch
 TrainingApp (iOS)                              TrainingWatch (watchOS app)
   TrainingAppKit (view models, iOS views)        TrainingWatchKit (session, views)   <- new
   TrainingKit: Core, Persistence,                TrainingKit: Core (+ zones, targets)
   HealthKit, WorkoutKit
        |                                              |
        |-- athlete zones + planned workout ---------->|   (§5)
        |<-- HKWorkout (+ route) via HealthKit --------|   (§6)
```

- A new **watchOS app target** `TrainingWatch` in `project.yml`, embedded in the iOS app. Bundle id `org.oekalegon.trainingapp.watchkitapp`.
- Session logic and view models go in a **new library target** (working name `TrainingWatchKit`, in TrainingAppKit or beside it) so they are testable with `swift test` on macOS, like the rest. The watchOS views stay thin.
- Anything that decides zones, targets or load stays in **TrainingKit** and is shared. The Watch never re-implements zone maths.

## 5. Getting zones and plans to the Watch

What the Watch needs: the athlete's zone model as of today (maximum, resting, threshold, method, resulting bpm bounds per zone; pace zones when MVP8 exists) and the day's planned workout with resolved steps.

Options:

| Option | For | Against |
|---|---|---|
| A. WatchConnectivity (`transferUserInfo` / `updateApplicationContext`) | Small payloads, simple, delivered when the Watch next wakes | Another channel to keep right; plan format needs a compact `Codable` snapshot |
| B. Shared CloudKit store (the Watch reads `TrainingPersistence` itself) | Same store, no second format | Watch-side sync is slower and less predictable; the whole store is more than a run needs; schema must be deployed for the Watch too |
| C. Keep WorkoutKit for plans, send only the zones | Planned workouts keep their existing path | Then the Watch app cannot run steps with its own display |

Leaning **A**: a small, versioned `WatchSnapshot` (`Codable`): zone model plus the next few days' resolved workouts, rebuilt on the same triggers as `WatchScheduleSync` (it can share its `requestSync` call sites). `updateApplicationContext` keeps only the latest, which is what we want.

The snapshot stores **resolved bpm bounds as well as the model inputs**, so a bug in one side's zone maths can't make the two disagree silently; the Watch shows what the iPhone computed, and a unit test checks both sides agree.

## 6. Recording

- `HKWorkoutSession` + `HKLiveWorkoutBuilder` on the Watch, with a running configuration and the venue from the plan (outdoor, track, treadmill, trail; see MVP2-151).
- **Steps:** a custom session does not get WorkoutKit's one-`HKWorkoutActivity`-per-step for free. The Watch app must add activities itself (`HKLiveWorkoutBuilder.addWorkoutActivity`) with the same `WOIntervalStepKeyPath` metadata (`block.repetition.step`, warm-up is block 0), so `ArrivedWorkoutImport` and the step cards work without change. **To verify early.**
- **Plan link:** the workout must carry what `HKWorkout.workoutPlan` carries today, or the importer must accept our own metadata key (preferred: a `TrainingApp` plan-id metadata key, matched ahead of the same-day heuristic).
- **Route:** `HKWorkoutRouteBuilder` fed by `CLLocation` updates, saved with the workout. This is also what unblocks the MVP4-100 map.
- **Zones stored with the workout:** put the zone bounds in effect (or a version of the athlete settings) in the workout's metadata. The importer can then show time in zone *as recorded*, and the iPhone and Watch cannot drift if the settings change later. Open question §9.
- **Distinguish our workouts:** metadata flag so the importer knows the source and can avoid double-importing when the athlete also ran Apple's Workout app.
- **Permissions:** HealthKit write (workout, route, the quantity types the builder records). New usage strings (`NSHealthUpdateUsageDescription` changes meaning: the app now writes). Location (when in use).

## 7. Watch UI

Screens (SwiftUI, watchOS 26):

1. **Start:** today's planned workout (from the snapshot) or "Free run"; venue.
2. **Workout pages** (swipe, Digital Crown), each a *data view* configurable per step kind later:
   - **Zone:** large heart rate, zone number and colour (athlete's zones), position inside the zone (Z3.4), time in zone.
   - **Step:** current step, remaining time or distance, target range, pace against the target (above, in, below), next step.
   - **Metrics:** time, distance, pace (current, average, lap), cadence, with the athlete's chosen set.
   - **Map:** live position, the trail so far, and the planned route when there is one; auto-centred and with a zoom on the Crown. MapKit on the Watch; the full route view stays on the iPhone (MVP4-100).
   - **Controls:** pause, end, lap, next step.
3. **Summary:** distance, time, average heart rate, time in zone with our zones, step results. Saves to Health.

Feedback: haptics on step change and when leaving the target range (heart rate or pace), our own because WorkoutKit alerts don't run in a custom session. Rules: debounce (no alert flapping around a boundary), a grace period at the start of a step, one alert type per step.

Always-on display, water lock and Action button behaviour need testing on a device.

## 8. iPhone side

- **Import:** the existing import already handles `HKWorkout`s. Additions: route import (shared with MVP4-100), zone metadata reading, our-source marker.
- **Settings (Athlete ▸ Apple Watch):** a switch for "use TrainingApp's zones on the Watch", the snapshot status (last sent), and a note on starting from the Watch.
- **Scheduling stays:** `WatchScheduleSync` keeps putting workouts in Apple's Workout app, so the athlete can choose either (decided, §9a). The importer handles a duplicate pair for one plan.
- **Activity sheet:** MVP4-100 gets the map from the Watch-recorded route.

## 9a. Decisions

- **WorkoutKit scheduling stays alongside the Watch app** (2026-11-06, Don). A planned run appears in Apple's Workout app (as today) and in the Watch app, and the athlete picks which to start. Apple's app remains a working fallback and a way to use the plan without the Watch app. Consequences:
  - The importer must cope with **two `HKWorkout`s for one planned run** (started in one app, then the other): when both link to the same plan, keep the one carrying our marker (§6) as the plan's activity and treat the other as a duplicate, using the existing deduplicate and join flow (MVP2-116) rather than a new one.
  - Time in zone for a workout from Apple's app uses TrainingApp's zones, as it does today. The Watch app only changes what is *shown and stored on the wrist*; it does not change how imports are scored.
  - Nothing is removed from `WatchScheduleSync`. A later switch to hide the Apple entry when the Watch app is in use is possible but not planned.
  - The athlete settings screen says which app uses which zones, so the difference is explicit rather than a surprise.

## 9. Open questions

1. ~~One workout, two apps?~~ Decided: keep both, see §9a.
2. **Step recording:** does a custom session's `addWorkoutActivity` produce what the importer expects? Needs a spike on a real Watch, including a plan without a warm-up or cool-down (the numbering question the MVP2-146 spike left open).
3. **Zones in the stored workout:** metadata bounds (reproducible, small), or recompute later from the dated settings (what happens today)? The history makes recompute right in the usual case; the metadata covers a changed maximum.
4. **Pace zones:** MVP8 has none yet. The Watch app v1 can run heart-rate zones and a pace range from the plan's step target (MVP5-141); full pace zones follow MVP8.
5. **Does everything TrainingAppKit needs build for watchOS?** TrainingKit declares `.watchOS(.v26)`, but `TrainingCore`'s and `TrainingPersistence`'s compile on watchOS are unchecked, and `TrainingAppKit` declares no watchOS. Check by building the targets for a watchOS destination.
6. **Source of truth for the snapshot:** WatchConnectivity (A) or reading the store on the Watch (B)? The Watch-side cost of B is not known.
7. **Free runs:** supported in v1, or planned workouts only?
8. **Data views:** fixed set per step kind, or configurable by the athlete? Start fixed.
9. **Battery and GPS:** long runs with a live map. A map page costs power; the map might draw only while visible.
10. **Release:** watchOS app needs its own App Store assets and a TestFlight path; the simulator can't give real GPS or heart rate, so most testing is on a device.

## 10. Phases

0. **Spike (no UI polish):** a watchOS target that records a run with `HKWorkoutSession`, fixed zone bounds, step activities with the metadata keys, saved to Health. Answers §9.2, §9.5. Check on the iPhone with Athlete ▸ Developer ▸ Inspect Recent Workouts that the import links and the steps match.
1. **Snapshot:** `WatchSnapshot` (zones plus planned workouts) over WatchConnectivity; the Watch shows the athlete's zones live.
2. **Planned workouts:** step engine, targets, haptics, the data pages.
3. **Route and map:** `HKWorkoutRouteBuilder`, live map page, route import on the iPhone (shared with MVP4-100).
4. **Zone metadata and polish:** zones in the workout, importer shows them, settings screen, always-on display, accessibility.
5. **Pace zones** after MVP8.

Phase 0 decides whether the rest is feasible as drawn; stop and rethink if the importer cannot accept our step activities.

## 11. Testing

- Step engine, target comparison, alert debouncing, snapshot encoding and the zone agreement between iPhone and Watch: unit tests on macOS (`swift test`), no device.
- A **session protocol** (`WorkoutSessionProviding`) hides `HKWorkoutSession` so the step engine runs against a fake with scripted heart rate, pace and location.
- Device checks (documented in the PR): live zones match the iPhone's, step changes land in Health as activities, the plan links, the route draws, and the summary's time in zone equals the iPhone's after import.
