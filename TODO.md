# TODO

Temporary todo list for TrainingApp and TrainingKit while the todo database is unavailable.
It was rebuilt on 2026-10-01 from git history, `TrainingKit/docs/roadmap.md` and the design docs, so the titles are paraphrased.

To mark an item done, change `[ ]` to `[x]` and add the date or PR, e.g. `(done 2026-10-03, #66)`.
New todos take the next free ID in their project. Items marked `MVP2-?` had no ID that could be recovered.

---

## In progress

- [ ] **MVP2-53** Refresh plans after import so auto-matched links show live. The TrainingKit part is merged (#63); the App's TrainingKit bump on `feature/mvp2-53-week-view-refresh` still needs a PR and merge.

## MVP2: Structured & Planned Workouts

- [ ] **MVP2-8** Label TRIMP as "estimated" vs "measured" everywhere it's shown (planned/no-HR activities)
- [ ] **MVP2-21** Workout library tab (also hosts MVP5's plan builder later)
- [ ] **MVP2-35** Decide the pace assumption for converting duration ↔ distance on planned cards (see `WeekViewModel.swift`)
- [ ] **MVP2-?** `Goal` model: a non-event target (e.g. "sub-20 5k") with no date and no calendar presence
- [ ] **MVP2-?** Structured Workout creator: create, edit, duplicate
- [ ] **MVP2-?** Extend `SessionType` to match the 14-workout library
- [ ] **MVP2-?** `StructuredWorkout.purpose` (`.general` / `.maxHRTest` / `.lthrTest`) and the MaxHR and LTHR field-test workouts (Friel 30-min)
- [ ] **MVP2-?** After a test workout: "we measured X, update your profile?" confirmation
- [ ] **MVP2-?** `AthleteProfile` tracks how MaxHR/LTHR was obtained (`.formula` / `.workout` / `.labTest`), plus manual lab-test entry
- [ ] **MVP2-?** Refine a workout's TRIMP estimate from the median actual TRIMP of its linked activities
- [ ] **MVP2-?** Leave missed planned workouts out of CTL/ATL/TSB, monotony/strain and the aggregate stats (check what is already done)
- [ ] **MVP2-?** *Merged* card state showing planned and actual together (check how much MVP2-43 covers)
- [ ] **MVP2-?** Race marker on the calendar that distinguishes primary from secondary/tertiary races
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
