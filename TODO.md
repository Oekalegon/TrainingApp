# TODO

Temporary todo list for TrainingApp and TrainingKit while the todo database is unavailable.
It was rebuilt on 2026-10-01 from git history, `TrainingKit/docs/roadmap.md` and the design docs, so the titles are paraphrased.

To mark an item done, change `[ ]` to `[x]` and add the date or PR, e.g. `(done 2026-10-03, #66)`.
New todos take the next free ID in their project; new IDs start at 100 (e.g. MVP2-100). Items marked `MVP2-?` had no ID that could be recovered.

---

## In progress

Nothing right now.

## MVP3: Calibration

- [ ] Reconcile MVP numbering between `trainingKit-design.md` and the todo projects
- [ ] `ResidualStore` of (expected, actual) load pairs from `PlanReconciler`
- [ ] `CalibratedPlanEstimator`
- [ ] Tune `TRIMPCoefficients` / `LoadModelParameters` / `PlanGuardrails` from observed data
- [ ] TRIMP per calorie and TRIMP per lean-mass metrics

## MVP4: Activity detail spillover

- [ ] Calendar `+` on a past date adds a completed activity manually
- [ ] **MVP4-100** A full activity sheet, replacing today's list of rows and sections (design it as one piece). Wanted: a **map** of the route (TrainingKit keeps only `Activity.geographicBounds` today, so it needs the workout's `HKWorkoutRoute` imported first); the heart-rate and pace charts and the step cards laid out together, so tapping a step highlights it where it can be seen (the charts sit above a long step list now, so the highlight is off screen until you scroll up: a sticky chart, or a side-by-side layout); the Watch's kilometre and mile **splits** (the `HKWorkoutEvent` segments the MVP2-146 spike found, ignored today); an elevation profile (only elevation ascended per step and in total is recorded today); the per-step power, stride length and ground contact the Watch records; weather (`HKWeatherTemperature` is in the workout's metadata); and the existing load, time in zone and plan link. Likely needs TrainingKit work for the route, the elevation series and the splits, and its own design doc section.

## MVP5: Plan Assistant

Scoping and design: `docs/design/mvp5-plan-assistant.md`.

- [ ] **MVP5-100** Write down triphasic (Run Elite): session profiles (interval work lengths, race-target fractions) per phase (conditioning, base, structural, specific, taper); blocks MVP5-103. Micro length (7/10/14, athlete choice), 6-week structural/specific and athlete-set sessions per micro are decided
- [x] **MVP5-101** (TrainingKit) Audit `PlanGuardrails`/`PlanEvaluator` for 7-day-week assumptions and fix, with tests using 10- and 14-day micros. Done in TrainingKit#109 (TrainingApp#146 drops the removed `PlanRule` cases from the app): build progression compares mean daily load; the CTL ramp, ATL/CTL ratio, recovery micro, meso progress, taper shape and consecutive load rules were removed; race-day TSB is a warning; the monotony window stays 7 days (a load-model setting) (done 2026-10-15, #146)
- [ ] **MVP5-102** (TrainingKit) `TrainingParadigm` data type, `PlanGuardrails.Overrides`, and new paradigm rules (`intensityDistribution`, `hardSessionSpacing`, `hardSessionsPerMicro`)
- [ ] **MVP5-103** (TrainingKit) Built-in paradigms: 80/20 polarized, triphasic
- [ ] **MVP5-104** (TrainingKit) `PlanPreferences` with `runAvailability: [Weekday: Set<DaySlot>]` (morning, afternoon/evening), independent of the paradigm
- [ ] **MVP5-110** (TrainingKit) `RunType` (easy, recovery, threshold, interval, long) mapped to `IntensityCategory`; `PlanPreferences.dayRunTypes: [Int: Set<RunType>]` (per micro day, several types allowed, tied to micro length); `maxWeeklyVolume` (peak, per 7 days); maps onto the generic `SessionType`, which stays small (the library's specifics live in the templates)
- [ ] **MVP5-111** (TrainingKit) Key-race handling in the generator: primary race anchors the macro, secondary gets a mini-taper and recovery, tertiary has none
- [ ] **MVP5-112** (App) Per-micro-day run type picker (multi-select; weekdays shown for 7/14-day micros, not 10) and the wizard; peak weekly volume field; key-race picker in the wizard
- [x] **MVP5-113** (TrainingKit) Split phase from load role: `CyclePhase` becomes a named, paradigm-defined value; add a micro load role (build/recovery/taper/race); backwards-compatible decoding of stored enum values; update the build-progression rule (the only one left that reads `.build`) or its MVP5-116 replacement (done 2026-10-15, #147)
- [ ] **MVP5-114** (TrainingKit) Intensity target for the specific phase: goal pace, target HR, perceived effort or predicted from fitness; goal on `Race`/`Goal`
- [ ] **MVP5-115** (TrainingKit) Generator compromises for short lead time (drop structural, then shorten specific) and conflict reporting (each overridden preference and why); optional conditioning phase
- [ ] **MVP5-116** (TrainingKit) Replace the `maxBuildProgressionFraction` rule with a longest-run rule (+10% over the longest run of the previous 4 weeks); update `PlanRule`, evaluator, tests
- [ ] **MVP5-117** (TrainingKit) Volume curve: per-micro targets in TRIMP/distance/time from start, ramp, peak (per 7 days), phase and role
- [ ] **MVP5-118** (TrainingKit) Template content analysis (interval work-length ranges) and per-phase session profiles; hard filter, closest fit, rotation, parameter progression
- [ ] **MVP5-119** (TrainingKit) Day assignment: availability by weekday, preferred run types by micro day, hard-session spacing, two-a-day
- [ ] **MVP5-120** (TrainingKit) Bounded adjust loop against `PlanEvaluator` and a plan proposal type listing findings and compromises (preferences overridden, shortened phases, missing templates); only `.risk` findings make a plan unacceptable, so also surface `.warning` findings (race-day TSB, high TSB) in the proposal
- [ ] **MVP5-121** (App) Plan preview and commit: layout, workouts, projected form, compromises, list of planned workouts to be replaced
- [ ] **MVP5-122** (TrainingKit) Resolve steps' intensity from athlete zones; fill work-step targets from a phase's fraction-of-race-target profile
- [ ] **MVP5-123** (TrainingKit/App) Re-plan from today, keeping paradigm, race and cycles, starting from current fitness
- [ ] **MVP5-105** (App) Running availability settings screen (weekdays, then slots per selected day)
- [x] **MVP5-106** (App) Make `WeekViewModel` period-aware (`DisplayPeriod`): no hard-coded 7 days in range, chart, load and cache keys; no visible change Done: `DisplayPeriod` (start + length, calendar-week factory) drives ranges, chart, load and cache windows (done 2026-10-15, #149)
- [x] **MVP5-107** (App) Show a 7/10/14-day micro-cycle when the selected date is inside a planned micro, else the calendar week; paging crosses the boundary; header shows macro › meso › micro and phase. Take neighbouring periods from the plan (they differ in length from a micro), update the design doc's "3-week" chart text, and test the DST boundary Done: planned micro (7/10/14 days) or calendar week, plan-derived neighbors, plan header strip (done 2026-10-15, #150)
- [x] **MVP5-108** (App) Rename `WeekView`/`WeekViewModel` to `MicroCycleView`/`MicroCycleViewModel` (mechanical PR, after MVP5-107) Done: types, files, tests and docs renamed, no behaviour change (done 2026-10-15, #151)
- [ ] `PlanPreferences` (training days, per-day sport/session type, starting volume, weekly ramp): see MVP5-104
- [ ] Create Plan wizard sheet
- [ ] `PlanGenerator`: lays out cycles with `CycleLayoutBuilder`, fills them with library workouts, iterates against `PlanEvaluator`
- [ ] **MVP5-5** Generator chooses workouts by intensity category
- [ ] Standard plans by target distance
- [ ] Goal management UI

## MVP6: AI Coach

- [ ] `TrainingTools` registry (`ToolRegistry`, `ToolSchema`, `PlanSandbox`) and its tool set
- [ ] `TrainingToolsAnthropic` adapter
- [ ] `TrainingToolsFoundationModels` on-device adapter
- [ ] Sandbox diff/commit confirmation UI

## MVP7: Athlete Tab History

- [ ] Show RHR / MaxHR / LTHR (and others) over time on the Athlete tab

## MVP8: Pace/Power Zones

- [ ] Scoping session (affects zone settings, TRIMP/load, `IntensityTarget`, guardrails)
- [ ] Marathon pace workout (from *Run Elite*): a run with a block at marathon pace. Needs a pace target, which the built-in templates can't express yet. Structure still to be specified

## FIT: Garmin/COROS import

- [ ] **FIT-1** FIT/TCX activity import
- [ ] **FIT-2** FIT workout export
- [ ] **FIT-3** Attach a raw .FIT file to backfill sparse-HR activities
- [ ] **FIT-4** Strava relay import (HR/GPS/elevation streams)
- [ ] **FIT-5** Per-activity import picker (.FIT or Strava) in activity detail
- [ ] **FIT-6** Automatic background Strava sync
- [ ] **FIT-7** Throttled historical backfill (first investigate whether Strava's rate limits allow it)
- [ ] **FIT-8** Cross-source duplicate detection and merge
- [ ] **FIT-9** Field-level conflict resolution on import

## Unassigned follow-ups (app design doc §5)

- [ ] (From MVP2-146) Fallback for the step markers and cards: an activity without stored steps (imported before the field, or not started from a plan) uses the `PaceHistory` estimate of each step's span and labels it approximate.
- [ ] Sync status / conflict UI
- [ ] Error presentation for pull-to-refresh failures
- [ ] Multi-athlete roster UI
- [ ] Cycle/plan viewing screen
- [ ] Edit the athlete account (needs a write path through `TrainingModel`)
- [ ] iPad layout
- [ ] watchOS companion

## Docs & tooling

- [ ] Switch CI to Xcode 27 once GitHub offers a `macos-27` runner image (`runs-on: macos-27` in both repos' `.github/workflows/swift.yml`). Until then CI builds with Xcode 26.6 (Swift 6.3) while development uses Xcode 27 (Swift 6.4), so code can build locally and fail in CI. That's what happened to TrainingKit#67: a local constant named after the method its initializer called. Until the switch, check TrainingKit changes against Xcode 26.6 before pushing.
- [ ] Fix the 38 existing TrainingKit DocC warnings (2026-10-01: TrainingCore 16, TrainingPersistence 10, TrainingTools 10, TrainingHealthKit 1, TrainingWorkoutKit 1). Most are ``links`` to symbols in another target; replace them with code voice. Then switch `trainingkit-pr-review` to `--warnings-as-errors`, and consider adding that check to CI.

---

## Done

### MVP2 (released as 0.2.0 on 2026-10-15)
- [x] **MVP2-1** Rename RacePriority cases; Race is a dated event (2026-09-21)
- [x] **MVP2-9** ~~Intensity colouring on cards~~: canceled, later brought back in MVP2-43/51
- [x] **MVP2-14** WorkoutTemplate model and built-in library (2026-09-17)
- [x] **MVP2-15** Create Planned Workout sheet with guardrail warnings (2026-09-18)
- [x] **MVP2-17** Race creation sheet and RaceStore (2026-09-22)
- [x] **MVP2-18** Loaded races feed the race-day TSB guardrail (2026-09-22)
- [x] **MVP2-19** PlanReconciler: auto-match, ambiguity flag, manual link/unlink (2026-09-21)
- [x] **MVP2-22** Day row "+" offers a planned workout or a race (2026-09-22)
- [x] **MVP2-29** xmark/checkmark toolbar buttons on PlannedWorkoutSheet (2026-09-18)
- [x] **MVP2-30** Daily Load chart split into planned vs performed (2026-09-19)
- [x] **MVP2-31** Stats bar shows planned and performed values (2026-09-20)
- [x] **MVP2-37** Planned activity card (2026-09-19)
- [x] **MVP2-38** Planned-workout detail sheet; deletePlan (2026-09-19)
- [x] **MVP2-39** Edit mode for date and load override; WorkoutKit unschedule (2026-09-19)
- [x] **MVP2-41** Edit a template workout's parameters (2026-09-21)
- [x] **MVP2-42** Link/unlink an activity to a plan (2026-09-21)
- [x] **MVP2-43** Intensity classification; planned-vs-actual values and missed plans on cards (2026-09-22)
- [x] **MVP2-51** Intensity marker icon instead of tint (2026-09-22)
- [x] **MVP2-53** Refresh plans after import so auto-matched links show live (2026-10-01, TrainingKit#63, #66)
- [x] **MVP2-54** Stats, load chart and pills refresh live; stats and daily-load caches now also key on an activity fingerprint (in-place changes such as a resync); missed plans confirmed uncounted (2026-10-05)
- [x] **MVP2-130** Heart-rate histogram cache refreshes when an activity's heart-rate samples change in place (same count): keyed on a fingerprint of the activities' samples instead of the count (2026-10-06, #93; found in the MVP2-54 review)
- [x] **MVP2-123** Redesign the Athlete tab as a settings-style list of groups (2026-10-06): Personal Information (avatar, name, sex, age; Heart Rate Zones and Pace Zones inside), Connected Services (Apple Health, Apple Watch ▸ Synchronisation), Calendar, Developer; the overlap warning stays on the list, and the Watch banner opens Apple Watch ▸ Synchronisation directly. Design doc §2.0/§2.3 updated.
- [x] **MVP2-124** Age in Personal Information: `AthleteProfile.dateOfBirth` and `age(asOf:)` in TrainingKit (TrainingKit#77), merged from HealthKit by the app (2026-10-06).
- [x] **MVP2-125** Apple Watch in Connected Services: one "Apple Watch" row, agreed with Don, because iOS lists no paired watches or their names (2026-10-06).
- [x] **MVP2-126** Apple Health in Connected Services: what the app reads, Import Now, and Connect Apple Health until something has been imported; it can't show which data types were allowed (2026-10-06).
- [x] **MVP2-120** Link an imported HealthKit workout to its plan by the `WorkoutPlan` id it was started from: exact match ahead of `PlanReconciler`'s same-day heuristic, same day only (2026-10-06, TrainingKit#76). The `HKWorkout.workoutPlan` lookup is untested on a device: check that a workout done from a Watch entry links to that exact plan.
- [x] **MVP2-121** HealthKit background delivery for workouts: `HKObserverQuery` with `enableBackgroundDelivery(.immediate)`, started at launch from `AppDelegate`; imports the workout, syncs the Watch, refreshes a running UI (2026-10-06). Not tried on a device: finish a Watch workout with the app closed and see it linked on the next launch.
- [x] **MVP2-56** Raise max HR from ordinary workouts: raise-only, athlete-confirmed, date-effective; 10 s held peak with cadence-lock and stuck-reading guards; one-time 12-month scan after the first import (2026-10-01, TrainingKit#65, #70)
- [x] **MVP2-101** Queued athlete updates: `TrainingModel.updateAthlete(asOf:_:)`, used by `applyMaxHeartRate` and the HealthKit merge, so the two can't overwrite each other (2026-10-01, TrainingKit#66, #71)
- [x] **MVP2-100** Daily calendar JSON export for a chosen period: share button in the week view toolbar, completed and upcoming planned workouts per day (missed left out) with TRIMP, sport/template/intensity, name, duration, distance, plus CTL/ATL/TSB/monotony/strain (2026-10-01, TrainingKit#67, #72)
- [x] **MVP2-102** Workout steps in the calendar JSON export: every entry has a `steps` array, repetitions expanded, with kind, goal, projected duration and distance and target; a completed activity carries its fulfilled plan's steps, empty without a plan (2026-10-04, TrainingKit#69, #72)
- [x] **MVP2-105** Interval workout templates: Base Full-out hill sprints, and Short interval run in time and track versions (2026-10-04, TrainingKit#70, #75)
- [x] **MVP2-150** The Athlete tab no longer shows the search field: `.searchable` moved from the tab view to the Week and Library tabs (2026-10-12)
- [x] **MVP2-145** Search from every tab's search field: the field is shared by all tabs but the results only existed in the search tab. The search tab is removed; the results are laid over whichever tab the field is used on (2026-10-12)
- [x] **MVP2-107** Import completed activities from a calendar export: added as placeholders with no heart rate and the file's TRIMP as an imported load; the export carries the HealthKit workout id so the real workout replaces its placeholder automatically (by id, or by sport and time overlap). Import preview and result show activities added and already in the log (2026-10-12, TrainingKit#92)
- [x] **MVP2-103** Calendar JSON import: planned workouts, rebuilt from their steps, with duplicates skipped, past entries skipped, and an edited TRIMP kept as a load override; completed activities and daily metrics aren't imported (activities are MVP2-107). Import Calendar button in the week view toolbar with a preview sheet (2026-10-04, TrainingKit#71, #76)
- [x] **MVP2-?** Missed planned workouts are left out of CTL/ATL/TSB (`DailyLoadSeries`) and the daily-load chart and stats (MVP2-30). Confirmed 2026-10-01
- [x] Verify MVP2-53 in the app after the next real workout: finish an activity that has a planned workout, sync, and check the week view shows one linked card without switching weeks (done 2026-10-05, verified on device)
- [x] **MVP2-8** Mark estimated values everywhere they're shown (planned TRIMP, pace forecasts, perceived-effort loads, projected days) with a "~"; measured values and a plan's targets (incl. a load override) stay plain (done 2026-10-05, #89)
- [x] **MVP2-21** Workout library tab (also hosts MVP5's plan builder later) (done 2026-10-05, #91): Library tab with the built-in templates by sport, a detail screen and "Plan This Workout"; a tab-bar search on every tab across templates, planned workouts and activities
- [x] **MVP2-35** Decide the pace assumption for converting duration ↔ distance on planned cards (see `WeekViewModel.swift`) (done 2026-10-05, TrainingKit#75, #81)
  - TrainingKit's `PaceHistory` and `HistoricalPaceEstimator` forecast from similar earlier workouts, per zone and per step, for the cards and the week's totals alike. Planned cards still show only the measure the workout defines; the detail sheet and linked cards show both.
- [x] **MVP2-55** Register planned workouts for the coming days in Apple Fitness, so each structured workout is available on the Watch on the day it's due, ideally first in the list. (done 2026-10-04, TrainingKit#74, #80; follow-ups MVP2-116 to MVP2-120)
  - [x] ~~Today a workout is scheduled only once, when its plan is saved (MVP2-15/39), through `WorkoutKitBridge.schedule`. Its doc says callers should schedule lazily within the ±7-day window the Watch shows, but nothing does that yet.~~ No longer true: `WatchScheduleSync` keeps the 7-day window scheduled (2026-10-04, #80).
  - [x] Needed: a rolling sync, on launch or foreground, that schedules plans in the window, keeps within `WorkoutScheduler`'s scheduled-workout limit, and unschedules entries for plans that moved or were deleted. (done 2026-10-04, #80)
  - [x] ~~**No duplicates:**~~ superseded by per-plan ids (TrainingKit#74): each entry carries its plan's id, so scheduling a plan again replaces its entry. Was: before scheduling, check `WorkoutScheduler.shared.scheduledWorkouts`. Skip a plan whose workout is already scheduled that day, matching by `workoutKitID` and also by equivalent steps, in case the same workout was added under another id.
  - [x] Find out whether WorkoutKit lets us control the order in the Workout app's list. Not needed: the Workout app lists scheduled workouts by date, like a calendar (checked on device 2026-10-05).
- [x] **MVP2-112** MVP2-55 (app): adopt per-plan Watch scheduling from TrainingKit. (done 2026-10-04, #80; the cleanup runs on every sync, not just once)
  - [x] Update callers: `unschedule(_:workout:calendar:)` becomes `unschedule(_:)`.
  - [x] Moving a plan or editing its workout now needs only `schedule`; remove the `unschedule` call before it.
  - [x] After upgrading, call `unscheduleAll(except:)` once with every plan ID in the store, so entries scheduled under the old IDs leave the Watch.
  - [x] Replace `sync(_:)` with `customWorkout(from:)` (via `PlannedWorkoutScheduling.validate`).
- [x] **MVP2-113** MVP2-55 (app): keep the Watch in sync with the plans. Builds on MVP2-112. (done 2026-10-05, #80; the rest moved to MVP2-116 to MVP2-120)
  - [x] Re-sync when the app opens or becomes active again: `WatchScheduleSync` puts the next 7 days on the Watch (2026-10-04, #80).
  - [x] Re-sync after a plan is saved, deleted or imported from a calendar (2026-10-04, #80).
  - [x] Re-sync on background refresh (works, checked on device 2026-10-05).
  - Re-sync after plan linking and after a HealthKit workout arrives: moved to MVP2-116.
  - [x] Ask for Watch permission (on the first sync with a plan to send, 2026-10-04, #80). A banner when it's denied: moved to MVP2-117.
  - [x] Turn it on by default (2026-10-04, #80): it runs whenever permission is granted.
  - A settings switch to turn it off: moved to MVP2-118.
  - A "sent to Watch" mark on plan cards: moved to MVP2-119.
- [x] **MVP2-116** (done 2026-10-05, #82) Re-run the Watch sync (`WatchScheduleSync.requestSync()`) after a plan is linked to or unlinked from an activity, and after a HealthKit workout arrives (import or background delivery), so a done plan's entry is kept and the window stays current. Today it runs on becoming active and after a plan is saved, deleted or imported from a calendar (MVP2-113).
- [x] **MVP2-117** (done 2026-10-05, #83) A dismissible banner when WorkoutKit permission is denied, explaining that planned workouts won't reach the Watch and how to allow it in Settings; the same kind of banner the roadmap describes for revoked HealthKit access.
  - [x] (done 2026-10-05, #84) Follow-up after testing on device: a yellow banner with a black icon, whose button opens the Athlete tab instead of iOS Settings; an Apple Watch section on the Athlete tab showing the permission, with an Allow button while not yet asked and, once declined, where to turn it back on (Watch app → Workout; iOS doesn't ask again). Logs WorkoutKit's state under the `WatchSync` category.
- [x] **MVP2-118** (done 2026-10-05, #85) A settings switch, "Send planned workouts to Apple Watch", on by default, in the Athlete tab's Apple Watch section (MVP2-117). Turning it off stops `WatchScheduleSync` and removes the app's scheduled entries; turning it on asks for permission if needed and syncs. Hide it when the device can't schedule workouts (`WorkoutScheduler.isSupported`).
- [x] **MVP2-119** (done 2026-10-05, #86) A "sent to Watch" mark on planned-workout cards for plans that are on the Watch, and a warning on a plan whose workout can't go on the Watch, with the reason ("Watch doesn't support this alert for cycling", from `validate`).
- [x] **MVP2-122** (done 2026-10-05, #87) Show the "can't go on the Watch" reason in the planned-workout detail sheet too, as on the card (MVP2-119): `WatchScheduleSync.unsupportedWorkouts` has it by workout id. Hidden while sending is turned off, like on the card.
- [x] **MVP2-129** (done 2026-10-06, TrainingKit#83) Search (MVP2-21) reads every activity with its heart-rate and speed samples to build its results, then drops the samples. Needs a TrainingKit summary query (e.g. `ActivityStore.activityListItems(in:)`: id, sport, start, duration, distance, linked plan) so opening the search tab stays fast with years of history (found in the #91 review). Done: search reads `ActivityStore.activityListItems(in:)`, which decodes only the list fields of each activity. Not measured on a large history.
- [x] **MVP2-139** (done 2026-10-09, TrainingKit#84, #109) `Goal` model: a non-event target (e.g. "sub-20 5k") with no date and no calendar presence. Done: `Goal` with a `GoalTarget` (time over a distance, a volume per week/month/year, or free text), a synced `GoalStore`, and `TrainingModel.goals`; nothing reads goals yet. The app's store set now includes the goal store. The CloudKit schema needs deploying to production before a release build syncs goals; the management UI is the MVP5 "Goal management UI" item, which should also validate a goal's numbers.
- [x] **MVP2-140** Structured Workout creator: create, edit, duplicate (done 2026-10-09, TrainingKit#85, #86, #110). The Library tab's "+" opens the creator; a template's detail screen has Edit, Duplicate and Delete. Built-in templates are read-only and can only be duplicated; the athlete's own are stored in a new synced `WorkoutTemplateStore` (TrainingKit: `WorkoutTemplateRecord`, `StoreSet.templateStore`, `TrainingModel.templates`). The planned-workout sheet, the Library, search and the calendar export all offer custom templates. Deleting a template that plans still use archives it instead of removing it (TrainingKit#86), so those plans keep it. The editor covers blocks with repeats, steps (kind, time/distance/open goal, heart-rate zone) and parameters that become sliders when planning. Not covered: pace, power, RPE and heart-rate-range targets can't be set (an existing one is kept), nor can blocks be reordered. The CloudKit schema needs deploying to production before a release build syncs templates.
- [x] **MVP2-141** (done 2026-10-10, TrainingKit#87, #113) Carry custom templates through calendar export and import. Before, an import rebuilt a workout from its steps without the template link, so a plan using a custom template came in as a plain workout whose parameters couldn't be edited. Wanted: the export includes the full definition (parameters and blocks) of each custom template a plan in the exported period actually uses; the import adds those templates to the library and re-links the imported workouts, with their parameter values. Before adding one, skip it if an equal template already exists (same sport, parameters and blocks; the name may differ) and link to that one instead. A template that arrives with an id already in the library but a different definition needs a rule (keep both, as a copy with a new id). Needs a format change in `CalendarExport`, so keep older files importing. Done: the export carries each custom template's definition and each planned entry's template id and parameter values (schema version stays 1); the import adds or links the templates, rebuilds workouts from them, copies on an id clash, and checks the file's values; the import preview and result list the template counts. Not tested on a real exported file on a device.
- [x] **MVP2-142** (done 2026-10-10, TrainingKit#87, #113) Include archived templates that a plan uses in the calendar export/import of MVP2-141, not only active ones (found while adding soft delete in MVP2-140). Same rule: the export carries the definition, the import adds it, skipping an equal one.
- [x] **MVP2-143** (done 2026-10-09, #111) Restyle the workout template detail and editor screens after how the Fitness app shows a structured workout: the steps as a visual sequence (warmup, work, recovery and cooldown as coloured segments sized by duration, repeats grouped), the zone or target shown on each step, instead of the current plain `Form` rows. Covers the Library's template detail screen and the creator/editor sheet (MVP2-140). Done as its own PR on top of the creator.
- [x] **MVP2-144** (done 2026-10-10, #112) Redesign planned workouts in the style of MVP2-143: the planned-workout detail sheet and the linked activity's detail ("Planned Steps") show the workout as the step cards of the template detail. The week view's cards are left as they are. Planned against actual per step is MVP2-146.
- [x] **MVP2-146** (done 2026-10-12, TrainingKit#90, #91; #117, #118, #119, #120, #121) Step markers and planned against actual per step on a linked activity. Wanted: markers on the activity's heart-rate and speed charts showing when each step actually started, lined up with the planned step cards, and each card showing what the athlete did (time, distance, pace, heart rate) beside what was planned. Today an `Activity` has only duration, distance and heart-rate and speed samples: no laps, segments or events. The HealthKit importer reads the heart rate and the id of the plan the workout was started from (`workout.workoutPlan`), not `workoutEvents` or `workoutActivities`. TrainingKit's `PaceHistory` already estimates each step's span by walking the speed track against the plan's steps (a time step by its duration, a distance step by the track's distance, an open step by a fixed time), but only for pace forecasts: the boundaries aren't stored and drift when the athlete paused or cut a step short.
  - [x] **Spike** (done 2026-10-11, tool: Athlete ▸ Developer ▸ Inspect Recent Workouts, #117). A long run started from a plan on the Watch (5 min warm-up, 10 km, 5 min cool-down) gave: the Watch **does record each step**, as one `HKWorkoutActivity` per step, with exact start and end (5:00, 65:22 and 4:59 long) and metadata `WOIntervalStepKeyPath` (`0.0.0`, `1.0.0`, `2.0.0`: warm-up, the block, cool-down), `WOIntervalStepSuccessful` (1 where the goal was met; absent on the last) and `HKElevationAscended` per step. The `HKWorkoutEvent` segments are **not** steps: two overlapping series of splits, about one per kilometre and about one per mile, running across step boundaries. The workout ran 3:52 past the last step with no step of its own. A hill-sprint workout (warm-up, run to the hill, 5 × [8 s sprint, 5 min recovery], run back, cool-down; 14 steps, 14 workout activities) confirmed the key path is `block.repetition.step`, all from 0: block 0 is the warm-up, the plan's blocks follow as 1…n, the cool-down is n+1 (`2.3.1` is block 2, 4th repetition, 2nd step), and each step ends where the next begins. Not yet seen: a plan **without** a warm-up or cool-down (whether the block numbers shift). **Per-step figures are recorded too**: each workout activity carries HealthKit statistics: `DistanceWalkingRunning` (sum; 801.65 m, 9993.82 m and 333.3 m for the three steps of the long run), `HeartRate` (average, in count/s: ×60 for bpm), `RunningSpeed`, power, stride length, ground contact, vertical oscillation, step count and energy. Distance is only readable once the athlete has allowed that type, which the app doesn't ask for yet (it reads workouts, heart rate, resting heart rate, sex and birth date), and TrainingKit imports no speed samples at all, so per-step figures come from these statistics, not from samples. The Inspect tool stays to check a plan without a warm-up.
  - [x] **Store the steps** (done 2026-10-12, TrainingKit#90; `ActivityStep`, `Activity.steps`, `ActivityStepAligner`, the distance read types): TrainingKit's HealthKit importer reads `workout.workoutActivities` that carry `WOIntervalStepKeyPath` and stores them on `Activity` (key path, start, end, active duration, distance, average heart rate, whether the goal was met, elevation ascended; pace is duration over distance), a new field in the local-only store that must decode activities written before it (tolerant decoding, legacy-payload test) and reach existing activities through Force Full Resync or a backfill. Then match them to the plan's expanded steps: block 0 is the warm-up, the plan's blocks follow, the last is the cool-down (to confirm for repeats), falling back to order. Time after the last step is shown as outside the plan.
  - [x] **Ask for distance access** (done 2026-10-12, #118): an "Allow distance" banner on the week view, shown while Health is connected and HealthKit has types never asked about, whose button asks and then re-reads all workouts once (this also gives earlier activities their steps) add the distance types (running/walking, cycling, swimming, rowing) to the Health read types and have existing installs ask once for them (`getRequestStatusForAuthorization` says whether any type is unanswered), since an install that already connected is never prompted again. Until it is granted, steps still carry their times and heart rate but no distance or pace.
  - **Fallback:** moved to the open follow-ups below (an activity without stored steps).
  - [x] **Step figures on the step cards** (done 2026-10-12, #118): the linked activity's steps show time, distance, average heart rate and average pace for each recorded step, one card per repetition of a repeat. Only one banner shows at a time now.
  - [x] **Heart-rate and pace charts with step markers** (done 2026-10-12, TrainingKit#91, #119): the activity detail has "Heart Rate Over Time" and "Pace Over Time" charts with a band and start line for each recorded step. TrainingKit now imports running and cycling speed (averaged over 5 s) for the pace chart; an existing install is asked once for distance and speed, then re-reads its workouts.
  - [x] **Tap a step card to highlight its span** (done 2026-10-12, #120): the card is tinted and the charts strengthen that band and fade the rest. The charts sit above the step cards, so with a long list the highlight is off screen until you scroll up; the full activity sheet (MVP4-100) is where that gets designed, so no sticky chart or scroll-to-chart is planned before it.
  - [x] **The time after the last step** (done 2026-10-12, #121): a card "After the plan" after the steps and a grey band on both charts (with a legend entry and VoiceOver wording), for the stretch the athlete went on past the plan: its time, the distance left over after the steps', the heart rate in it and the pace. Not shown when the last step ends within 30 s of the end. Also: the estimated fallback for an activity without recorded steps (`PaceHistory`'s spans, labelled approximate, heart rate only since TrainingKit imports no speed samples), and showing a step's goal-met flag.
- [x] **MVP2-149** (done 2026-10-12, TrainingKit#93, TrainingApp#125) The week view's stats bar counts a plan twice once it is done. The planned totals (`~46 km`, `~5:06:35`, `~482`) include every plan dated today or later, even one already matched to a completed activity (`completedActivityID != nil`), so today's finished 12 km run shows again as ~11 km of planned distance, and its time and load likewise. Seen on Sun 11 Oct 2026: performed 35 km + today's planned ~11 km = the ~46 km shown, while every planned workout was done. The test race adds nothing (it has no workout). Cause: `StatisticsCalculator.periodStatsSplit` (TrainingKit, `plansInRange`) deliberately does no plan-to-activity matching. Fix: skip plans with `completedActivityID != nil` there, the same filter `WeekViewModel.pendingPlans(on:)` uses for the day list; apply it in `WeekViewModel.weekEstimates` too so the estimate markers agree; update the doc comment and any `StatisticsCalculatorPeriodStatsSplitTests` case that expects a matched plan to count. Needs a TrainingKit change. Done: both filters added, plus a test for a matched plan; no existing test expected one to count.
- [x] **MVP2-151** (done 2026-10-12, #130, TrainingKit#95 and #96) (TrainingKit + App) Set the venue in the workout sent to the watch, so starting a planned run doesn't ask "Indoor or Outdoor?". The planned activity gets a specific sport (indoor run, outdoor run, trail run; the other sports likewise where they have variants), mapped to the WorkoutKit custom workout's location type (`Sport+WorkoutKit` currently notes that HealthKit has no separate indoor/outdoor activity type, so check what `CustomWorkout` offers). A template may fix the sport itself (e.g. the track interval session in multiples of 400 m is outdoor), in which case the plan inherits it and the picker is hidden or locked; otherwise the plan editor lets the athlete choose, with a default. Done: `Venue` is separate from `Sport` (trail, track and treadmill runs are all `.running`, so the stats see one sport). The create sheet preselects the template's default venue for the athlete and hides the picker (shows a read-only row) when the template fixes it; editing re-instantiates with the venue; the template editor can fix a venue; the activity detail has a sport and venue picker (and "Use Planned …" when the plan's differ); Personal Information sets the main sport and usual venue.
- [x] **MVP2-152** (done 2026-10-12, #129) Name a linked activity's card after its planned workout (e.g. "10 km Long Run") instead of the sport's name. Once a plan is matched to an activity the activity's card, and anywhere else that shows its title, uses the workout's name; an activity the athlete has named themselves keeps that name. Needs a check that a manual name is distinguishable from the default (an empty/nil name vs. a stored one), and the name should follow when the link is made or released. Done: the card and the detail sheet show the plan's workout name; `Activity` has no name field, so nothing manual needs protecting yet (a rename feature would take precedence).
- [x] **MVP2-157** (done 2026-10-13, #136) Tell the athlete why a field test couldn't be measured (`FieldTestError`: no heart rate, effort not located, effort too short, ...), e.g. on the test activity's detail sheet with a hint such as "start the test from the Watch workout". Today `WeekViewModel.checkForFieldTestResult()` skips such a test silently.
- [x] **MVP2-153** (done 2026-10-13, TrainingKit#97) (TrainingKit) `StructuredWorkout.purpose` (`.general` / `.maxHRTest` / `.lthrTest`), carried from a template to its workout, persisted, and decoding old data as `.general`. Plus the two field-test templates in the built-in library: the max HR test (warm-up, three hard efforts with short recoveries, an all-out final effort) and Friel's 30-minute LTHR test (warm-up, then 30 minutes all-out). Settle the exact protocols first.
- [x] **MVP2-154** (done 2026-10-13, TrainingKit#98) (TrainingKit) Measure a test workout's result from the activity linked to its plan: max HR test = the highest heart rate held for a few seconds (reuses MVP2-56's `PeakHeartRateDetector`); LTHR test = the average heart rate over the last 20 minutes of the 30-minute effort. Unlike MVP2-56, a max HR result from a test may also **lower** the max, and only for a linked test activity; ordinary workouts still only raise it. `AthleteProfile` tracks how LTHR was obtained, like `maxHeartRateSource`; decide the source for a test result (`.workout(activityID:)` or a new `.fieldTest`). Needs MVP2-153.
- [x] **MVP2-155** (done 2026-10-13, #135) (App) After a test workout: "We measured X. Update your max heart rate / LTHR?", with an option to keep the old value; reuses the max HR prompt of MVP2-56. Needs MVP2-154.
- [x] **MVP2-156** (done 2026-10-13, #134) (App) The two test workouts in the library, and a purpose option in the template editor. Needs MVP2-153.
- [x] **MVP2-158** (done 2026-10-13, #137, TrainingKit#99) (App) Lab tests in the app. TrainingKit#99 added `.labTest(measuredOn:)` to `MaxHeartRateSource` and `LactateThresholdSource` and ranked the sources by reliability (`reliabilityRank(asOf:)`, `isReplaceable(by:asOf:)`; a lab test ranks below a field test after 2 years for max HR, 90 days for LTHR). In the app: (1) handle `.labTest` in the switch over `MaxHeartRateSource` in `AthleteViewModel` (the app follows TrainingKit `develop`, so this breaks the build once it resolves); (2) the HealthKit formula merge checks `maxHeartRateSource.isReplaceable(by: .formula, asOf: today)` instead of `== .formula`; (3) the heart-rate editor can record a maximum or LTHR as a lab test, with its date; (4) the field-test prompt (MVP2-155) and the raise prompt (MVP2-56) say when `replacesMoreReliableSource` is set, e.g. "This replaces a lab-tested value".
- [x] **MVP2-159** (done 2026-10-13, #138) Refine a workout's TRIMP estimate from the median actual TRIMP of its linked activities (TrainingKit#100, #101, #102; the app's cards, stats and sheets use it, see "Refined planned load" in the design doc)
- [x] **MVP2-160** (done 2026-10-13, TrainingKit#103, #140) (TrainingKit + App) `TrainingModel.refinedEstimator()` reads the whole plan history and scores every completed activity on each call, and logs a store failure instead of reporting it. Cache the estimator on the model (invalidated with the recompute) and offer a throwing variant, so the app can refresh cheaply after an import and tell "no completed plans" from "couldn't read" (today `WeekViewModel.refreshPlannedLoadIfNeeded` treats a base estimator after a refined one as a failed read). Measure the refresh on a large store.
- [x] **MVP2-161** (done 2026-10-14, TrainingKit#105) (TrainingKit) `TrainingModel.importActivities` recomputes even when nothing was upserted or deleted, and `recompute` always rebuilds the refined estimator (MVP2-160), so a pull-to-refresh that finds nothing new still pays a build (about 0.4 s per 400 completed one-hour runs, debug build, linear in the history). Rebuild only when something that feeds the estimator changed: have the mutators that change data mark it stale, and let `recompute` rebuild when it is. The date rollover still needs the metrics recompute, not the estimator. Measure with `RefinedEstimatorLargeStoreTests`.
- [x] **MVP2-104** (done 2026-10-07, #104) Race marker on the calendar that distinguishes primary from secondary/tertiary races. Week view day rows done (race card with an A/B/C circle, #74); The Form chart marks each race with a solid vertical rule and a circled A/B/C on top. Not yet looked at on a device.
- [x] **MVP2-106** (done 2026-10-14, TrainingKit#104, #141) More interval workout templates from the roadmap's library (long and mixed intervals, fartlek, fast finish, hill reps, ...), and check the planned-workout sheet's sliders on the new templates: the sprint, repetition and recovery sliders are continuous, so a rest can land on an odd number of seconds.
- [x] **MVP2-108** (done 2026-10-11, #114) Show planned workouts on the week view before any Health data is imported. On a fresh install the "No training data yet" empty state hides the day rows, so a calendar import (MVP2-103) or a new plan shows no sign it exists until Health is connected. Found on the simulator, which has no Health data. Done: the empty state shows only while nothing is imported and no plan is loaded (`WeekViewModel.showsEmptyState`); plans in weeks that aren't loaded don't count until those weeks are shown. With plans but no Health data, the week view has no "Connect Health Data" prompt, only the Athlete tab's Apple Health row.
- [x] **MVP2-109** Group the week view's three trailing toolbar buttons in a "..." (`ellipsis`) menu, which is what Apple uses now instead of a hamburger. With the previous/next-week buttons on the left and three buttons on the right, the toolbar is too wide, so the week title no longer shows when scrolling down. Keep the previous/next-week buttons as they are; check the title appears in the collapsed state on the smallest supported iPhone. (done 2026-10-04, #77)
- [x] **MVP2-110** Default titles for planned workouts, built from the template's parameter values instead of just the template name: "50min Easy Run", "23 km Long Run", "10x8sec Hill Reps". Today `PlannedWorkoutSheetViewModel.workoutName` starts as `selectedTemplate.name` and updates only when the template changes. The logic belongs in TrainingKit, which owns the templates and knows which parameter is the duration, distance or repetition count; the calendar export/import and any future plan generator then get the same title. (done 2026-10-04, TrainingKit#72, #73 and #79)
  - **TrainingKit:** a function from a template and its values to a title, with tests for every template. Return structured pieces or take a unit system/formatter, so units ("min", "sec", "km" vs miles) follow the user's locale and settings.
  - **TrainingApp:** bump the TrainingKit pin (as in MVP2-105) and use the generated title as the sheet's default name. It keeps following the sliders until the athlete edits the name by hand; that state stays in `PlannedWorkoutSheetViewModel`, with tests.
- [x] **MVP2-111** Estimate a planned workout's likely duration from previous workouts made with the same template. Open-ended steps (the run to the hill in the hill-sprint template) are ignored in default titles and count as a fixed 10 minutes in planned-duration estimates (`WorkoutDurationEstimator`), so the two can disagree; the median of earlier linked activities would be closer. Related to the TRIMP refinement item above. (done 2026-10-05, TrainingKit#75, #81)
  - Open steps take the median time they took in earlier linked runs of the same workout or template.
- [x] **MVP2-114** After the TrainingKit MVP2-35/111 PR merged, point `TrainingAppKit/Package.swift` back at TrainingKit's `develop` and pin `Package.resolved` to the merge commit. (done 2026-10-05, TrainingKit#75, #81)
- [x] **MVP2-115** Unify how a planned step's zone is chosen: `WorkoutDurationEstimator` assumes zone 3 for a distance step without a `.heartRateZone` target, while the projector, the TRIMP estimator and the pace forecast use `HeartRateZoneModel.intensityRatio` (zone 4 for a `.pace`/`.power` target). Found in the MVP2-35/111 review; changing it moves existing load and duration estimates, so it needs its own PR in TrainingKit.
- [x] **MVP2-132** Edit the athlete profile (2026-10-06, TrainingKit#78, #97): name; avatar (a photo from the library, kept small on the profile); heart-rate settings (resting and maximum, lactate threshold, zone method as an inline picker) and threshold pace, each dated with a history list; week start and time zone. Resting HR follows Apple Health through a switch (not editable while on); a changed maximum is accepted by the athlete (typed in, or the age estimate offered), never applied automatically. Time zone and week start apply to all history and rebuild the fitness history once. Design doc §2.3 updated.
- [x] **MVP2-131** Split the persistence container so health-derived data stays off iCloud (2026-10-06, TrainingKit#79, #99): plans, workouts, cycles, races and the athlete's preferences sync; activities, joins, tombstones, the metrics cache and the whole profile are local-only. Migrates an old store, keeping `default.store.pre-split`. Not tried on a real CloudKit store or device yet; old records stay in iCloud until the app's iCloud data is deleted.
- [x] **MVP2-133** The MVP2-131 split checked on the device (2026-10-06): activities, plan links, deleted duplicates and the profile all survived the migration. Left for the athlete when ready: delete `default.store.pre-split` and the app's old iCloud data (Settings, Apple Account, iCloud, Manage Storage).
- [x] **MVP2-134** (done 2026-10-06, TrainingKit#80) Make completed plans consistent across devices after the MVP2-131 split: a synced plan's `completedActivityID` names an activity only the importing device has, so a second device can show the plan as done with no activity. Options: derive `Activity.id` from the HealthKit workout's uuid so every device agrees, and repair plan links on load. Only matters with more than one device. Done: a new HealthKit import takes `Activity.id` from the workout uuid, and a plan held by an activity this device lacks is freed when an imported workout names it as its scheduled plan. Activities imported earlier keep their random ids, so they still differ between devices. Not tried with two devices.
- [x] **MVP2-135** (done 2026-10-07, #105) Race markers on the daily-load page and on the metric detail charts (Load, Fitness, Fatigue, Form), as on the Form chart (MVP2-104 review). One shared `RaceChartMarkers` overlay; the detail charts take the races of their loaded buffer. Not yet looked at on a device.
- [x] **MVP2-137** (done 2026-10-08, #107) Return the races with `WeekViewModel.metrics(in:)` for the metric detail charts, so their load-before-read ordering is enforced and the buffer fetch can be tested outside the view (MVP2-135 review). Done: `WeekViewModel.chartBuffer(in:asOf:)` returns the metrics, load split and races together (loading the range first), and the detail view takes one `bufferProvider`.
- [x] **MVP2-138** (done 2026-10-08, #108) Load a metric detail chart's range once: `WeekViewModel.chartBuffer(in:asOf:)` loads it twice, once for the metrics and once for the load split, on every pan or period change (MVP2-137 review). Done: one `loadWindow(covering:asOf:)` shared by `metrics(in:)`, `dailyLoadSplit(in:)` and `chartBuffer(in:)`, which now loads once and reads all three with no suspension between.
- [x] **MVP2-127** A day row's Load pill carries a "~" when one of that day's activities was scored from perceived effort (2026-10-06).
- [x] **MVP2-128** `WeekViewModel.scoredLoad(for:)` is cached per activity, shared by the card, the stats bar's estimate flags and the Load pill (2026-10-06; done with MVP2-127).
- [x] **MVP2-147** (done 2026-10-11, #115) Onboarding: HealthKit and CloudKit permissions block first launch; a later revocation shows a dismissible banner. Also covers the case MVP2-108 left open (the former MVP2-147): while nothing has been imported from Health but plans exist (Health skipped, denied or never asked about, then a calendar import or a plan), the week view shows the same "Connect Health Data" banner, since the full empty state is hidden once a plan is loaded and the Athlete tab's Apple Health row is the only other way to connect. HealthKit doesn't reveal whether read access was granted, so "revoked" has to be inferred; see the Apple Health row in the design doc (Connected Services). Done: a first-run introduction (Health and iCloud, each skippable, Continue leaves it), an iCloud-unavailable banner, and a Connect Health Data banner for plans without an import; a Health revocation can't be detected, so there's no banner for it. Not done: initial-sync progress; the Health banner isn't seen on screen on a fresh install (needs a plan); the introduction on macOS.
- [x] **MVP2-148** (done 2026-10-11, TrainingKit#89) Run the calendar template import (MVP2-141) against `SwiftDataStore` as well as `InMemoryStore`: the model-level test that imports a file with a custom template, checks the template, workout and plan are stored and linked, and that a second import adds nothing. The import goes through the `WorkoutTemplateStore` protocol, so this covers the CloudKit-backed path. Done: four tests in `SwiftDataTemplateImportTests` (store and read back the template, a second import adds nothing, an id clash stored as a copy, an equal template linked); no source changes were needed.

### MVP1 (released as 0.1.0 on 2026-09-17)
- [x] **MVP1-1** InMemoryStore
- [x] **MVP1-9** TrainingTools infra
- [x] **MVP1-10** Cycles/statistics/evaluator tests
- [x] **MVP1-11** Athlete identity
- [x] **MVP1-13** Import activities
- [x] **MVP1-15** Week view
- [x] **MVP1-16** Activity detail
- [x] **MVP1-17** Athlete view
- [x] **MVP1-18** Athlete HealthKit prefill
- [x] **MVP1-19** Week swipe animation
- [x] **MVP1-20** Drop day headers and rest-day rows
- [x] **MVP1-21** Fitness-metrics cache
- [x] **MVP1-22** Hiking sport; force-resync UI
- [x] **MVP1-23** Remove week title
- [x] **MVP1-25** Fetch predicate; ActivityRecord.start backfill
- [x] **MVP1-26/27/28** Duplicate activities from overlapping imports
- [x] **MVP1-29** Overlap detection
- [x] **MVP1-30** CloudKit remote-notification background mode
- [x] **MVP1-32** Week chart flash
- [x] **MVP1-33** TRIMP dots on the fitness chart
- [x] **MVP1-34** Highlight the current week
- [x] **MVP1-38** Dashed future lines
- [x] **MVP1-39** Timeline with weekday pills
- [x] **MVP1-40** CTL/ATL/TSB pills
- [x] **MVP1-41** Activity timeline cards
- [x] **MVP1-44** Deduplicate button
- [x] **MVP1-45** Fitness metrics info sheet
- [x] **MVP1-46** TSB zone classification
- [x] **MVP1-47** 80/20 split (Kit)
- [x] **MVP1-48** 80/20 split (App)
- [x] **MVP1-51** HR zone names and colors
- [x] **MVP1-52** Main-sport stats pager
- [x] **MVP1-53** Main sport (Kit)
- [x] **MVP1-55** Paged graph panel
- [x] **MVP1-56** Week view title
- [x] **MVP1-59** Fitness cache wipe and its cleanup
- [x] **MVP1-60** Per-graph info panel
- [x] **MVP1-61** HR histogram overshoot
- [x] **MVP1-62** Rename to Heart Rate Histogram
- [x] **MVP1-63** Overlap warning UI
- [x] **MVP1-64** Soft-delete activities
- [x] **MVP1-65** Delete activity button
- [x] **MVP1-66** coreTraining mapped to strength
- [x] **MVP1-67** Overlap warning on the Athlete tab
- [x] **MVP1-68** Core Strength Training sport
- [x] **MVP1-70** All HR zones with colored dots
- [x] **MVP1-71** HR zones overview on the Athlete tab
- [x] **MVP1-72** Load/TRIMP explanation
- [x] **MVP1-73** Fitness/CTL explanation
- [x] **MVP1-74** Fatigue/ATL explanation
- [x] **MVP1-75** Form/TSB explanation
- [x] **MVP1-76** Time-in-zone paging and LIT
- [x] **MVP1-77** Time-in-zone bar chart
- [x] **MVP1-78** Date-effective zones in weekly time in zone
- [x] **MVP1-79** Resting HR median smoothing
- [x] **MVP1-80** Join split activities (2026-09-21)
