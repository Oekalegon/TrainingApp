# TODO

Temporary todo list for TrainingApp and TrainingKit while the todo database is unavailable.
It was rebuilt on 2026-10-01 from git history, `TrainingKit/docs/roadmap.md` and the design docs, so the titles are paraphrased.

To mark an item done, change `[ ]` to `[x]` and add the date or PR, e.g. `(done 2026-10-03, #66)`.
New todos take the next free ID in their project; new IDs start at 100 (e.g. MVP2-100). Items marked `MVP2-?` had no ID that could be recovered.

---

## In progress

- [x] Verify MVP2-53 in the app after the next real workout: finish an activity that has a planned workout, sync, and check the week view shows one linked card without switching weeks (done 2026-10-05, verified on device)

## MVP2: Structured & Planned Workouts

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
- [ ] **MVP2-129** Search (MVP2-21) reads every activity with its heart-rate and speed samples to build its results, then drops the samples. Needs a TrainingKit summary query (e.g. `ActivityStore.activitySummaries(in:)`: id, sport, start, duration, distance, linked plan) so opening the search tab stays fast with years of history (found in the #91 review).
- [ ] **MVP2-?** `Goal` model: a non-event target (e.g. "sub-20 5k") with no date and no calendar presence
- [ ] **MVP2-?** Structured Workout creator: create, edit, duplicate
- [ ] **MVP2-?** Extend `SessionType` to match the 14-workout library
- [ ] **MVP2-?** `StructuredWorkout.purpose` (`.general` / `.maxHRTest` / `.lthrTest`) and the MaxHR and LTHR field-test workouts (Friel 30-min). Reuses MVP2-56's peak detection and update prompt. Unlike MVP2-56, a test result may also **lower** max HR.
- [ ] **MVP2-?** After a test workout: "we measured X, update your profile?" confirmation
- [ ] **MVP2-?** `AthleteProfile` tracks how MaxHR/LTHR was obtained (`.formula` / `.workout` / `.labTest`), plus manual lab-test entry
- [ ] **MVP2-?** Refine a workout's TRIMP estimate from the median actual TRIMP of its linked activities
- [ ] **MVP2-?** *Merged* card state showing planned and actual together (check how much MVP2-43 covers)
- [ ] **MVP2-104** Race marker on the calendar that distinguishes primary from secondary/tertiary races. Week view day rows done (race card with an A/B/C circle, #74); chart marker not yet.
- [ ] **MVP2-106** More interval workout templates from the roadmap's library (long and mixed intervals, fartlek, fast finish, hill reps, ...), and check the planned-workout sheet's sliders on the new templates: the sprint, repetition and recovery sliders are continuous, so a rest can land on an odd number of seconds.
- [ ] **MVP2-108** Show planned workouts on the week view before any Health data is imported. On a fresh install the "No training data yet" empty state hides the day rows, so a calendar import (MVP2-103) or a new plan shows no sign it exists until Health is connected. Found on the simulator, which has no Health data.
- [ ] **MVP2-107** Import completed activities from a calendar export file (the rest of MVP2-103). Needs the model to hold an imported load for an activity without heart-rate data: `LoadMethod.manual` exists, but `Activity` has no field for it, so this means a new optional field with SwiftData and CloudKit persistence changes and a migration. Decide how it deduplicates against activities HealthKit imports later.
- [x] **MVP2-109** Group the week view's three trailing toolbar buttons in a "..." (`ellipsis`) menu, which is what Apple uses now instead of a hamburger. With the previous/next-week buttons on the left and three buttons on the right, the toolbar is too wide, so the week title no longer shows when scrolling down. Keep the previous/next-week buttons as they are; check the title appears in the collapsed state on the smallest supported iPhone. (done 2026-10-04, #77)
- [x] **MVP2-110** Default titles for planned workouts, built from the template's parameter values instead of just the template name: "50min Easy Run", "23 km Long Run", "10x8sec Hill Reps". Today `PlannedWorkoutSheetViewModel.workoutName` starts as `selectedTemplate.name` and updates only when the template changes. The logic belongs in TrainingKit, which owns the templates and knows which parameter is the duration, distance or repetition count; the calendar export/import and any future plan generator then get the same title. (done 2026-10-04, TrainingKit#72, #73 and #79)
  - **TrainingKit:** a function from a template and its values to a title, with tests for every template. Return structured pieces or take a unit system/formatter, so units ("min", "sec", "km" vs miles) follow the user's locale and settings.
  - **TrainingApp:** bump the TrainingKit pin (as in MVP2-105) and use the generated title as the sheet's default name. It keeps following the sliders until the athlete edits the name by hand; that state stays in `PlannedWorkoutSheetViewModel`, with tests.
- [x] **MVP2-111** Estimate a planned workout's likely duration from previous workouts made with the same template. Open-ended steps (the run to the hill in the hill-sprint template) are ignored in default titles and count as a fixed 10 minutes in planned-duration estimates (`WorkoutDurationEstimator`), so the two can disagree; the median of earlier linked activities would be closer. Related to the TRIMP refinement item above. (done 2026-10-05, TrainingKit#75, #81)
  - Open steps take the median time they took in earlier linked runs of the same workout or template.
- [x] **MVP2-114** After the TrainingKit MVP2-35/111 PR merged, point `TrainingAppKit/Package.swift` back at TrainingKit's `develop` and pin `Package.resolved` to the merge commit. (done 2026-10-05, TrainingKit#75, #81)
- [ ] **MVP2-115** Unify how a planned step's zone is chosen: `WorkoutDurationEstimator` assumes zone 3 for a distance step without a `.heartRateZone` target, while the projector, the TRIMP estimator and the pace forecast use `HeartRateZoneModel.intensityRatio` (zone 4 for a `.pace`/`.power` target). Found in the MVP2-35/111 review; changing it moves existing load and duration estimates, so it needs its own PR in TrainingKit.
- [x] **MVP2-132** Edit the athlete profile (2026-10-06, TrainingKit#78, #97): name; avatar (a photo from the library, kept small on the profile); heart-rate settings (resting and maximum, lactate threshold, zone method as an inline picker) and threshold pace, each dated with a history list; week start and time zone. Resting HR follows Apple Health through a switch (not editable while on); a changed maximum is accepted by the athlete (typed in, or the age estimate offered), never applied automatically. Time zone and week start apply to all history and rebuild the fitness history once. Design doc §2.3 updated.
- [x] **MVP2-131** Split the persistence container so health-derived data stays off iCloud (2026-10-06, TrainingKit#79): plans, workouts, cycles, races and the athlete's preferences sync; activities, joins, tombstones, the metrics cache and the whole profile are local-only. Migrates an old store, keeping `default.store.pre-split`. Not tried on a real CloudKit store or device yet; old records stay in iCloud until the app's iCloud data is deleted.
- [ ] **MVP2-133** Check the MVP2-131 split on the device before relying on it: launch the new build, confirm activities, plan links, tombstones and the profile are all still there, then delete `default.store.pre-split` (and the app's old iCloud data) once happy. If something is missing, the backup has the original.
- [ ] **MVP2-134** Make completed plans consistent across devices after the MVP2-131 split: a synced plan's `completedActivityID` names an activity only the importing device has, so a second device can show the plan as done with no activity. Options: derive `Activity.id` from the HealthKit workout's uuid so every device agrees, and repair plan links on load. Only matters with more than one device.
- [x] **MVP2-127** A day row's Load pill carries a "~" when one of that day's activities was scored from perceived effort (2026-10-06).
- [x] **MVP2-128** `WeekViewModel.scoredLoad(for:)` is cached per activity, shared by the card, the stats bar's estimate flags and the Load pill (2026-10-06; done with MVP2-127).
- [ ] **MVP2-?** Onboarding: HealthKit and CloudKit permissions block first launch; a later revocation shows a dismissible banner

## MVP3: Calibration

- [ ] Reconcile MVP numbering between `trainingKit-design.md` and the todo projects
- [ ] `ResidualStore` of (expected, actual) load pairs from `PlanReconciler`
- [ ] `CalibratedPlanEstimator`
- [ ] Tune `TRIMPCoefficients` / `LoadModelParameters` / `PlanGuardrails` from observed data
- [ ] TRIMP per calorie and TRIMP per lean-mass metrics

## MVP4: Activity detail spillover

- [ ] Calendar `+` on a past date adds a completed activity manually

## MVP5: Plan Assistant

- [ ] `PlanPreferences` (training days, per-day sport/session type, starting volume, weekly ramp)
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

### MVP2
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
- [x] **MVP2-103** Calendar JSON import: planned workouts, rebuilt from their steps, with duplicates skipped, past entries skipped, and an edited TRIMP kept as a load override; completed activities and daily metrics aren't imported (activities are MVP2-107). Import Calendar button in the week view toolbar with a preview sheet (2026-10-04, TrainingKit#71, #76)
- [x] **MVP2-?** Missed planned workouts are left out of CTL/ATL/TSB (`DailyLoadSeries`) and the daily-load chart and stats (MVP2-30). Confirmed 2026-10-01

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
