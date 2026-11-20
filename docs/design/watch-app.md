# Watch app: requirements

Status: WATCH-101 is built and tested in the simulator (a run saves to Health with its route; the real-watch check is deferred until a watch is available). WATCH-102 onwards are open: see `TODO.md`.

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

Controls: pause and resume, and a manual lap button. Steps **auto-advance** on their time or distance end condition, and the lap button also moves on manually.

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

### Audio

- Announces step changes, such as "Interval 3 of 6, 4 minutes, zone 4".
- Only through earbuds. Never from the watch speaker; haptics only otherwise (to confirm).
- Pauses **podcasts** and ducks **music**. Use an audio session with `.interruptSpokenAudioAndMixWithOthers`, plus ducking for music.

The thresholds (smoothing window, hysteresis, slope threshold, escalation timing) start as proposed defaults and are tuned in real runs.

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

## Battery monitoring and hand-off to the iPhone (wanted, needs a spike)

- Monitor the watch battery during a run and warn when it runs low.
- When it gets too low and the iPhone is near, hand the recording off to the iPhone, which records the rest. That includes heart rate when an external monitor is connected.
- Open feasibility questions: how the iPhone continues the same workout (a mirrored `HKWorkoutSession` versus a new session on the phone and stitching the two), whether the phone can read a Bluetooth HR strap itself, and what the saved `HKWorkout` looks like afterwards (one workout or two). Without the watch's wrist HR the phone only has the external monitor, so a run with no strap would lose HR.


## Testing in the simulator

The simulator records no heart rate, distance or route, so debug builds for the simulator fake them (`#if targetEnvironment(simulator)` in `watchOS/Sources`):

- **Heart rate:** a synthetic ramp from 90 to 170 bpm and back, written to the workout builder once a second.
- **Distance:** summed from the location fixes the simulator plays back and added to the builder as one sample per batch. Each sample must stay inside the collection window (from the previous sample's end to now): a sample stamped with a fix's own timestamp can predate the builder's start, and HealthKit then puts the builder into an error state ("Unable to transition … from the Error(7) state") and the run can't be saved. The builder's own distance statistic stays near zero in the simulator even then, so simulator builds show the replayed sum instead and the distance of the saved workout in Health can't be trusted there. The screen also shows the number of fixes received.
- **Route:** the fixes go to an `HKWorkoutRouteBuilder` as on a real watch.
- **`-autostart` and `-autoend <seconds>` launch arguments:** start a run without tapping Start, and end it after that many seconds (the Health permission sheet still needs one tap the first time).

To drive GPS from a recorded track, simulator builds play a GPX file themselves, with no `simctl location` and no location permission. The simulator shares the Mac's file system, so the app reads the file directly. Put a `.gpx` file in `~/Documents/TrainingWatchGPX/` (the first one by name is played). Nothing else to set up. To use another file or tune the playback, set the `gpxPath`, `gpxSpeed` (default 10) and `gpxStartMinute` defaults, for example as launch arguments (`-gpxPath /path/track.gpx`) or with `xcrun simctl spawn <UDID> defaults write org.oekalegon.trainingapp.watchkitapp gpxSpeed 30`.

Empty the folder (and delete any `gpxPath` default) to use CoreLocation again. The debug line on the metrics page then reads `location GPX replay`. The older `Tools/replay-gpx.py` still works for driving CoreLocation through `simctl location`; run it once with `--prime` before starting the run and pass `--device <UDID>`. Keep GPX files out of the repo: they hold real locations. Build for the simulator with ad-hoc signing (`CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO`), not `CODE_SIGNING_ALLOWED=NO`, or the HealthKit entitlement is missing and the app shows "Missing com.apple.developer.healthkit entitlement".
