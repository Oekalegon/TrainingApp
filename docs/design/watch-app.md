# Watch app: requirements

Status: WATCH-101 to WATCH-106 are built (WATCH-106's alerts are unit-tested, not yet run in the simulator or on a watch) (a run saves to Health with its route; the real-watch check is deferred until a watch is available). WATCH-107 onwards are open: see `TODO.md`.

## Why

The Workout app on the Apple Watch cannot use the athlete's own heart-rate zones. This app is a small watchOS app that records a workout with `HKWorkoutSession` and `HKLiveWorkoutBuilder` (so it saves a normal `HKWorkout` to Health) and coaches the run with TrainingApp's own zones.

## Scope

**v1**

- Platform: watchOS 26 minimum, matching the iOS 26 target.
- Activity: outdoor running only.
- Order of work: planned workouts first, free recording second.
- Fully standalone during a run: today's plan and the zones are cached on the watch, the run is saved on the watch, and it syncs later. A dropped phone link must not affect a run.
- The existing `WatchSchedulePlanner` / `WatchScheduleSync` path to the Workout app stays. The new app is an alternative.

**Later (not v1)**

- Several workout pages, configurable from the iOS app (which pages, and which metrics each holds).
- A map page, with workout metrics on it.
- Free recording (a run with no plan) and other activity types (cycling, swimming, strength).

## Data in

- **HR zones** are owned by TrainingApp and synced to the watch (mechanism open, see below). The watch looks up bpm bounds from them.
- **Planned workout** for today (and a few days ahead) is synced to the watch. Step targets are a **zone number (1 to 5)**, resolved to bpm on the watch from the synced zones. This matches the zone-position model of MVP5-148.

## Workout screen (v1)

One fixed page showing:

- total elapsed time
- time remaining in the step, or distance remaining, depending on the step's end condition
- the step's target, shown to suit its type (zone with the current bpm and a colour band)

**As built (WATCH-105)**, on the metrics page (`RunMetricsPage`), which is the default page, with the controls one swipe to the right:

- **In a planned workout**, from the top: the step's place, kind, goal and target ("4/14 20 s Z4"); what is left of the step as the big number (a clock, or the distance left, or "Open" for a step that waits for the lap button); a bar for how far through the step the run is; the step's heart-rate target as a name and bpm range ("Z4 163-177") over a gauge, with the target band in green and a marker for the current heart rate; the heart rate itself, coloured blue below the target, green in it and red above it, with the words next to it ("10 bpm above", "In target") so the colour isn't the only signal; the total time and the distance, small; and the next step ("Next: Recovery 20 s Z2", "Last step"), or "Paused".
- **Target forms:** a whole zone, a stretch of zones (positions, such as 4.0-4.5) and a bpm range all resolve to bpm on the watch (`StepHeartRateTarget`, tested). A pace, power or RPE step with no heart-rate target, or a zone target with no zones yet, shows the zone the heart rate is in instead.
- **In a free run**, and after the last step ("Workout done"): the total time as the big number, the zone the heart rate is in, the heart rate and the distance.
- **Controls page:** next step (or lap), pause and resume, and end with a confirmation. The simulator's debug lines (fixes, location, events) are at the bottom of this page.
- The gauge and the colours show only where the heart rate is against the target right now. When to alert is `ZoneAlertEngine` (WATCH-106, see Alerts below).

Controls: pause and resume, and a manual lap button. Steps **auto-advance** on their time or distance end condition, and the lap button also moves on manually.

## Target zone dial (WATCH-118)

A second run screen for a planned workout, drawn by the user in FreeForm (2026-11-23; the drawing was white on black the wrong way round, so the real screen is white text on black): a bar with all the zones on one line shows where the heart rate is against the **target zone**.

- **Bar:** all the zones on **one horizontal line** (`ZoneDialBar`) in their own order, zone 0 (below zone 1, grey) on the left to zone 5 on the right, so a rising heart rate moves to the right. **Every zone is the same size except the target zone, which is three times as wide** and drawn **bright** and taller; the others are a **darker** shade of their zone's colour (the shared `HeartRateZone.zoneColor`). The target is therefore a bit to the left of the middle for a low target zone and to the right of it for a high one. **When the target zone changes, the line is laid out again** and the zones glide to their new places (`ZoneDial.spans(target:length:)` blends two layouts). Earlier versions drew a ring round the screen (a rounded rectangle open at the bottom, one with a gap for the clock, then a circle) and then a line with the target always in the middle and the lower zones squeezed to its left; none of them gave a clear picture.
- **Triangle:** under the bar, pointing up at the heart rate's position along the zones (`ZoneBands.position(forHeartRate:)`: 2.5 is halfway through zone 2, zone 0 spans one zone 1 width below zone 1, above zone 5 it stays at the right end). In its zone's stretch it is by how far through the zone the heart rate is. The geometry is `ZoneDial`.
- **Text,** top to bottom, the values to the **left** and the interval to the **right**: the step's **countdown** (time or distance left; "Open" for an open step) in yellow, with **which interval it is** to the right of it as x/y ("5/12" for the fifth of a block repeated 12 times); a step that is not in a repeat (a warm-up, a cool-down, a single run) shows no interval number; the heart rate's place as "Zone 2.3" (rounded down; the word "Zone" small, 14 pt) at the left and the bpm at the **right** with its "BPM", in large type (32 pt); the bar; and the **total workout time**. The two timers have the same, large size (up to 50 pt, a quarter of the screen's width). The watch's own clock at the top right can't be hidden without private API, so the content starts below it (as far down as the safe area's top inset, or at least 30 pt: `minimumClockHeight`, a guess to check on a watch). VoiceOver gets one sentence with all of it, including whether the heart rate is below, in or above the target, since the colours say nothing to it.
- **Colour:** the zone's value and the bpm are **white** in the target (and when the step has no target), **blue below** it and **red above** it, so a glance says whether to speed up or slow down. The "Zone" and the "BPM" are always in the secondary colour. The background stays black. The state has a margin of a tenth of the target's width, at least 1 bpm, beyond a bound before it changes, so a heart rate on a bound doesn't flicker the colour. (An earlier version coloured the whole background dark blue or dark red; the colour is on the text now.)
- **A target that is part of a zone** (such as Z4.0-4.5 or 150-160 bpm): the whole target zone is in the darker shade, and only the target's stretch of it is bright, so the bar agrees with the colour and the alerts.
- **A step with no heart-rate target** (a pace, power or RPE step, or no zones yet) has no zone for the top: the bar keeps zone 3 as the target there, with no zone bright and only the triangle moving, so it doesn't re-lay itself at every zone boundary.
- **Where:** a page of a planned workout between the controls and the metrics, and the page the workout opens on; free runs have the metrics page only. A page order and a choice of pages is WATCH-109. The page moves to the dial when the steps start and back to the metrics when the last one ends, but only from that page, so someone on the controls page stays there.
- **To tune on a real watch:** the clock's height (30 pt), the bar's height (14 pt), the dark shade (40% opacity), the blue and red of the text, the target's width (three times the others), and the text sizes on the smaller watches.

## Alerts

### Trigger

- Compare a **smoothed HR** (rolling average over about 5 to 10 s) with the target zone's bounds, with a hysteresis margin of a few bpm.
- An alert always fires at the **start of a step**, announcing the new target.
- When the gap to the target is larger than a zone width (for example zone 1 to a zone 5 target), stay quiet while smoothed HR is **rising fast enough** toward the target (a slope threshold in bpm per 10 s). Alert only when HR is not rising enough.
- Always alert when HR **enters** the target zone.

### Repeat

Escalating: the longer HR stays outside the target zone, the more often or the more strongly it repeats.

### Telling too high from too low

- Different haptic patterns for too low (speed up) and too high (slow down).
- A distinct confirmation cue when back in zone.
- Spoken cue ("Slow down", "Zone 3") or tones, in earbuds. **Speech or tones is a setting.**

### One signal per meaning (added 2026-11-21)

Every kind of event gets its own haptic pattern and its own tone, so the wrist and the ears tell them apart without looking. Today a step change plays one `.notification` haptic (and `.success` at the end of the workout), made in WATCH-104; WATCH-117 gives each of these its own:

- **Step started** (a new target): its own signal, unlike every zone alert below.
- **Too low** (below the zone) and **too high** (above it): different from each other.
- **Back in the zone**: different from both out-of-zone signals and from the step signal.
- **Far out of the zone** (well beyond the hysteresis margin, or out for long): a third, more urgent pattern, such as a short tone repeated, instead of the ordinary out-of-zone one. Above and below stay distinguishable in it too.
- The workout's last step ending keeps its own.

**Which channel (decided 2026-11-21):**
- **Headphones or earbuds connected:** zone alerts (below, above, back in, far out) are **sound only**, as a tone or speech by the WATCH-107 setting, with no haptic. That also keeps the wrist still for the heart-rate sensor.
- **No headphones:** zone alerts are **haptic only**. The watch speaker is never used.
- **Step started** and **workout done** may use the haptic as well as the sound, with or without headphones, since they are rare and the wrist is a good place to feel a step change.
- Whether headphones are connected is read when an alert fires, not once at the start, so putting them in or taking them out mid-run changes the channel.

The haptic and the tone for an event are chosen together from one table (event to haptic pattern and tone), so they can't drift apart, and speech (the WATCH-107 setting) says the same thing in words. WATCH-106 decides when each event fires; WATCH-117 decides what each sounds and feels like. Haptic patterns can only be judged on a real watch, which is a few months away, so start with `WKHapticType` values that already differ clearly and tune later.

### Audio

- Announces step changes, such as "Interval 3 of 6, 4 minutes, zone 4".
- Only through earbuds. Never from the watch speaker; haptics only otherwise (to confirm).
- Pauses **podcasts** and ducks **music**. Use an audio session with `.interruptSpokenAudioAndMixWithOthers`, plus ducking for music.

The thresholds (smoothing window, hysteresis, slope threshold, escalation timing) start as proposed defaults and are tuned in real runs.

### As built (WATCH-106)

`ZoneAlertEngine` (`TrainingWatchKit`) is a pure value: `beginStep(target:at:)` at each step start and `add(_:at:)` for each reading, on the run's own clock (paused time left out). The target is a plain range and the reading is in one unit where higher means harder, so the same engine can serve heart rate (bpm) and, later, pace targets (as speed, MVP8-101). Heart rate and pace behave differently (heart rate lags the effort by tens of seconds and is smooth; pace follows it at once and is noisy, and a runner can stop or sprint within seconds), so every threshold is in a `ZoneAlertEngine.Settings` preset per signal. `RunRecorder+Alerts.swift` feeds the engine in a planned workout and `ZoneAlertHaptics` plays the haptic.

Heart rate (`Settings.heartRate`):
- Smoothed value: mean of the last 3 s. Hysteresis: a tenth of the target's width, at least 1 bpm (1.35 bpm on a 13.5 bpm zone); out of the zone at that margin beyond a bound, back in at the bound itself.
- Out-of-zone alerts wait 2 s after a step starts, so the step's own alert is heard first. The step-start alert is the old step-change haptic (`.notification`); the workout's end keeps `.success`.
- Slope rule: quiet while the heart rate moves toward the zone by at least 3 bpm per 10 s (a line over the last 10 s) and the gap is wider than the zone, or would be closed within 20 s at that speed. With too few readings to tell (under two, or less than 2 s apart), a gap wider than the zone waits for them, for 10 s at most after a step starts or a run resumes (it is usually the climb, and a watch may report only every few seconds); any other alert goes ahead.
- Entering the zone from outside gives "back in zone" (a step that starts inside the zone gives none).
- Repeats every 20 s while out, every 10 s after 60 s out; the far variant when three quarters of the zone's width (at least 5 bpm) beyond a bound, or out for 90 s. The time out of the zone keeps counting while the slope rule keeps quiet, so a long climb that stalls gets the far alert at once.

Pace (`Settings.pace`, placeholder values for MVP8-101, not tuned on any run): a wider margin, a wait of 4 s out of the target before the first alert (a lone GPS fix is not a pace), no slope rule, a 5 s grace and quicker repeats. A pace step has no alerts yet, since only heart-rate targets resolve (`StepHeartRateTarget`).

Pause and resume:
- Every pause (the button or the system) forgets the readings, in the session delegate.
- The readings after a resume are held back for one smoothing window (3 s), so a lone reading can't alert.
- Zones arriving in the middle of a step are picked up at the next reading, without an alert.

Haptics only for now, the same whether or not headphones are connected: the headphones channel and the sound are WATCH-107, the final patterns WATCH-117. The haptics are `directionUp`, `directionDown` and `success`, the far ones twice. To see them in the simulator, use the alert test run (`-fakeAlertPlan`, see "Testing in the simulator" below): the 20 s steps of the interval track are too short for most alerts, since the first comes a few seconds into a step and the average lags. The logic has unit tests; the recorder wiring has none (WATCH-113).

## Results

- Save the run as an `HKWorkout` through `HKLiveWorkoutBuilder`.
- Also write **step or lap `HKWorkoutEvent`s**, so the activity detail can show splits per step.
- TrainingApp's existing HealthKit import picks the workout up, as it does for the Workout app today.

## Decisions (WATCH-100, 2026-11-20)

- **Sync:** both. WatchConnectivity pushes the zones and the next few days of plan instantly when the phone is reachable. CloudKit (the shared `iCloud.org.oekalegon.trainingkit.shared` container, via TrainingPersistence) is the fallback, so the watch can refresh without the phone. Add a manual refresh on the watch.
- **Plan match:** tag the `HKWorkout` metadata with the planned workout ID for an exact match. The existing time-and-type matching stays as the fallback for runs recorded in the Workout app.
- **Shared code:** the watch target uses the TrainingKit packages directly (TrainingCore, TrainingPersistence and so on). A new small package in this repo, `TrainingWatchKit` (watchOS 26 plus macOS so `swift test` works), holds the step engine, alert logic and audio cues. `TrainingAppKit` stays iOS-only.
- **Signing:** companion app `org.oekalegon.trainingapp.watchkitapp`, embedded in the iOS app, sharing its iCloud container, HealthKit entitlement and team.
- **Units and language:** follow the athlete's setting in TrainingApp, falling back to the system's. Speech uses the watch's language.
- **Auto-pause:** off in v1 (manual pause only).
- **Display:** the standard always-on behaviour with no custom dimmed layout. Alerts rely on haptics and audio.
- **GPS:** outdoor running configuration with an `HKWorkoutRouteBuilder`, so the route is saved. A low-power mode (reduced GPS sampling for long runs) is wanted but comes after v1.

## Zones on the watch (WATCH-102)

- The phone sends the athlete's current `HeartRateZoneSettings` (not precomputed bpm ranges), so the watch uses the same `HeartRateZoneModel` and can't disagree about a boundary, whichever zone method is set. `AppTabView` sends them through `WatchZoneSync` when the app becomes active and whenever the settings change, only when they differ from what was last sent.
- Transport is a WatchConnectivity application context (`WatchSyncChannel`): only the newest zones matter, and the system delivers the latest one when the watch app next runs. The phone holds the zones until the session is active and a watch with the app installed is paired.
- The watch keeps the last zones in `UserDefaults` (`WatchZoneStore`), so a run can start with the phone out of reach.
- The metrics page shows the current zone as a coloured "Z3" with its bpm range, "<Z1" below zone 1, and "No zones yet" until some arrive. The colours come from one definition in `TrainingWatchKit` that the phone's charts use too. This is the raw current heart rate; only the alerts smooth it (WATCH-106).
- The CloudKit fallback for a phone that isn't reachable is WATCH-114.
- Simulator: `-fakeZones` gives the watch zones (resting 55, maximum 190) when no phone has sent any.

## Plan on the watch (WATCH-103)

- The phone reads only the plans of the next 7 days (today included) and the workouts they use, and sends the planned runs among them that have a workout and aren't completed, earliest first (`WatchPlanSync`). Only runs, because the watch app records runs; other sports stay on the Workout app's schedule. Each entry is the planned activity's ID, its date, the workout's name and its steps as TrainingKit's own `WorkoutBlock`s, so the watch reads step goals (time, distance, open) and targets exactly as the phone does. Nothing else of the phone's workout travels (library and template IDs, parameters, purpose), so the payload stays to what the watch uses.
- The zones and the plan are one WatchConnectivity context (`WatchContext`): an application context replaces the one before as a whole, so sending them separately would let each wipe the other out. A part the phone hasn't sent yet is `nil` and the watch keeps what it has; an empty plan is "nothing planned" and clears the old one. Each part is decoded on its own, so one the watch can't read (a phone updated before the watch) is left out and the other still arrives.
- Each plan carries when it was sent (`sentAt`). The phone sends again when the plan changes and at least every 6 hours while its app is used, so a plan older than 24 hours means the phone hasn't been opened: the start screen then adds "Plan from 3 days ago: open TrainingApp to update", so "No run planned today" isn't mistaken for "the phone hasn't said".
- `WatchScheduleSync` runs the plan sync at the start of each of its runs, so it follows the moments the Workout app's schedule does (the app becoming active, a plan saved, deleted or imported, a link or unlink). It doesn't follow the Athlete tab's "Send Planned Workouts to Apple Watch" switch, which is about the Workout app's schedule, and it doesn't need WorkoutKit permission.
- The watch caches the plan (`WatchPlanStore`), so a run can start with the phone out of reach. "Today" is the watch's own calendar day, so it is where the athlete is. The start screen lists today's workouts with their steps as short lines (`WatchWorkoutSummary`, for example "4 × (3 min Z4, Recovery 2 min Z2)"), or says no plan has arrived or no run is planned.
- Starting a workout with its steps, auto-advance and the live step display come with the step engine (WATCH-104, WATCH-105); until then "Start run" records a free run. Pace and power targets aren't shown (a step with a pace target shows its heart-rate companion's zone), and the run isn't tagged with the planned activity's ID yet (WATCH-104).
- Simulator: `-fakePlan` gives the watch an interval workout planned for today, `-fakeStalePlan` the same sent 3 days ago; neither is cached.

## Steps on the watch (WATCH-104)

Decisions from the scoping Q&A of 2026-11-20:

- **Starting:** each of today's workouts on the start screen is a button; tapping it starts a run with that workout's steps. "Start run" stays a free run with no steps.
- **Advancing:** `WorkoutStepEngine` (in `TrainingWatchKit`, pure logic, tested) lays the workout's blocks out as steps, each repetition of a repeated block its own step. A step with a time or distance goal ends when it is reached (time from workout time, so paused time doesn't count; distance from the run's distance); an open step waits for the lap button. The next step starts where the last goal ended, so time goals don't drift by the update interval. The recorder checks twice a second.
- **Lap button** (on the controls page, "Next step" during a workout, "Lap" otherwise): ends the current step and moves on (a press within a second of the step beginning is ignored, so a double tap doesn't skip two), and the saved workout records a lap event at that moment, so a step cut short can be told from one that ended by itself. In a free run, or after the last step, it only records a lap event.
- **After the last step** the run keeps recording as a free run until End. The step line says "Workout done" in green.
- **One haptic** at each step change, whether it came from a goal or the lap button, and a different one when the last step ends. That haptic is now the step-start alert of `ZoneAlertEngine` (WATCH-106); the zone alerts have their own haptics, and the patterns and audio are WATCH-117 and WATCH-107.
- **Saved workout:**
  - A segment `HKWorkoutEvent` per step, from when the step started to when it ended, dated by the engine's own step boundary (not when the half-second tick noticed it) and including any pause inside the step, with the step's index, kind, repetition, goal and how it ended ("goal", "lap" or "workoutEnded") in the event's metadata. A step still going when the run ends gets its segment too. Events that fail to write are kept and tried again with the next batch and just before the workout is ended.
  - A lap event for each lap-button press.
  - The `HKWorkout` is tagged with the planned activity's ID and the workout's name, so a run can be matched to its plan exactly. The keys are in `WorkoutMetadata`; they are custom, since HealthKit reserves the ones that start with "HK".
  - TrainingApp doesn't read these yet (WATCH-116): its import matches by time and type as before, and shows the events as it did for the Workout app's.
- **Screen:** the metrics page shows a basic step line: the step's place ("3/6"), its text ("Recovery 4 s Z2") and what is left ("0:04 left", "9 m left", or "Press Lap to move on" for an open step). The full run screen is WATCH-105.
- Simulator launch arguments (all in `SimulatorTestData` and `SimulatorTestHooks`; they do nothing on a real watch):
  - `-fakeZones`: the athlete's zones (resting 55, maximum 190).
  - `-fakeShortPlan`: a workout of steps a few seconds long (and a 15 m cool-down).
  - `-fakeAlertPlan` (WATCH-106): a 14-minute workout for the zone alerts: 60 s warm-up, 4 × (90 s zone 4, 90 s zone 2), 60 s cool-down (`TestWorkouts.alertTest`). Use it with `-gpxPath .../alert-test.gpx` (`make-interval-gpx.py --alert`), whose heart rate leaves the step's zone for a stretch in most steps: hard 2 goes above zone 4 and far above, hard 3 below and far below, hard 4 never gets there (155), easy 2 above zone 2, easy 3 below it, easy 4 stays above (158); the first hard and easy steps stay in their zones, as the quiet case. `AlertTestTrackTests` replays the track through `ZoneAlertEngine` and keeps the alerts it gives in step with this.
  - `-fakeIntervalPlan`: a 6-minute workout: 60 s warm-up, 6 × (20 s zone 4, 20 s zone 2), 60 s cool-down (`TestWorkouts.intervals`).
  - `-gpxPath <file>`: the GPX to play. `Tools/TestTracks/short-intervals.gpx` is a synthetic track that follows the interval workout step for step, with a heart rate that moves towards each step's level over a few seconds, so the first seconds of each hard step are still below zone 4. Some steps deliberately leave their zone, to test the alerts: the 2nd hard step goes far above zone 4 (about 188 bpm), the 4th far below it (about 140), the 6th a little below (about 158); the 3rd easy step goes below zone 2 (about 129) and the 5th above it (about 155). `Tools/make-interval-gpx.py` makes it; it is no real place. `TestWorkoutTrackTests` keeps it and the workout in step.
  - `-autostartPlan` starts today's first workout, `-autolap <after>` presses the lap button, and the simulator's debug line shows how many events were written. The metrics page of a planned workout shows the last three zone alerts with their run time in a small line at the bottom (the simulator plays no haptics), newest first.
  - While one of the fake arguments is given, what a paired phone sends is ignored.
- **From Xcode** the TrainingWatch scheme (in `project.yml`) passes `-fakeZones`, `-fakeAlertPlan`, `-autostartPlan` and `-gpxPath $(SRCROOT)/Tools/TestTracks/alert-test.gpx`, so a run on a watch simulator starts the 4 × 90 s alert test workout on that track by itself (since WATCH-106; before it the 6 × 20 s interval run). Untick them under Product > Scheme > Edit Scheme > Run > Arguments for a normal run. For the 20 s interval run, untick `-fakeAlertPlan` and the `alert-test.gpx` path, and tick `-fakeIntervalPlan` and the `short-intervals.gpx` one. A repo path with spaces breaks the `-gpxPath` one.
- **From the command line** pass the same arguments to `xcrun simctl launch`, with the GPX's full path.

## Battery monitoring and hand-off to the iPhone (wanted, needs a spike)

- Monitor the watch battery during a run and warn when it runs low.
- When it gets too low and the iPhone is near, hand the recording off to the iPhone, which records the rest. That includes heart rate when an external monitor is connected.
- Open feasibility questions: how the iPhone continues the same workout (a mirrored `HKWorkoutSession` versus a new session on the phone and stitching the two), whether the phone can read a Bluetooth HR strap itself, and what the saved `HKWorkout` looks like afterwards (one workout or two). Without the watch's wrist HR the phone only has the external monitor, so a run with no strap would lose HR.


## Testing in the simulator

The simulator records no heart rate, distance or route, so debug builds for the simulator fake them (`#if targetEnvironment(simulator)` in `watchOS/Sources`):

- **Heart rate:** the GPX's own heart rate when a GPX is being played and has one, written to the workout builder at each fix; otherwise a made-up ramp from 90 to 170 bpm and back, once a second.
- **Distance:** summed from the location fixes the simulator plays back and added to the builder as one sample per batch. Each sample must stay inside the collection window (from the previous sample's end to now): a sample stamped with a fix's own timestamp can predate the builder's start, and HealthKit then puts the builder into an error state ("Unable to transition … from the Error(7) state") and the run can't be saved. The builder's own distance statistic stays near zero in the simulator even then, so simulator builds show the replayed sum instead and the distance of the saved workout in Health can't be trusted there. The screen also shows the number of fixes received.
- **Route:** the fixes go to an `HKWorkoutRouteBuilder` as on a real watch.
- **`-autostart` and `-autostartPlan`, `-autoend <seconds>`, `-autopause <after>,<for>` and `-autolap <after>` launch arguments:** start a run without tapping Start (or start today's first planned workout), end it after that many seconds, pause it after `<after>` seconds for `<for>` seconds, and press the lap button after `<after>` seconds (the Health permission sheet still needs one tap the first time).

To drive GPS from a recorded track, simulator builds play a GPX file themselves, with no `simctl location` and no location permission. The simulator shares the Mac's file system, so the app reads the file directly. Put a `.gpx` file in `~/Documents/TrainingWatchGPX/` (the first one by name is played). Nothing else to set up. (The file is read by `GPXTrack` in `TrainingWatchKit`, which has tests.) To use another file or tune the playback, set the `gpxPath`, `gpxSpeed` (default 1, the track's real speed) and `gpxStartMinute` defaults, for example as launch arguments (`-gpxPath /path/track.gpx`) or with `xcrun simctl spawn <UDID> defaults write org.oekalegon.trainingapp.watchkitapp gpxSpeed 30`.

The replay stops while the run is paused. A `gpxSpeed` (or other) default set earlier overrides these defaults until it is deleted with `defaults delete org.oekalegon.trainingapp.watchkitapp gpxSpeed`. Empty the folder (and delete any `gpxPath` default) to use CoreLocation again. The heart rate is played only by this in-app replay; `Tools/replay-gpx.py` drives CoreLocation through `simctl`, which has no heart rate, so with it the made-up ramp is what the watch shows. The debug line on the metrics page then reads `location GPX replay`. The older `Tools/replay-gpx.py` still works for driving CoreLocation through `simctl location`; run it once with `--prime` before starting the run and pass `--device <UDID>`. Keep GPX files out of the repo: they hold real locations. Build for the simulator with ad-hoc signing (`CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO`), not `CODE_SIGNING_ALLOWED=NO`, or the HealthKit entitlement is missing and the app shows "Missing com.apple.developer.healthkit entitlement".
