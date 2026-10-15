# MVP5 — Plan Assistant: scoping

Status: draft for review. Covers TrainingKit (model, generator, guardrails) and TrainingApp (views, wizard, settings). Todo IDs are MVP5-1xx in `TODO.md`.

## 1. What already exists

| Piece | Where | State |
|---|---|---|
| Macro / meso / micro | `TrainingCycle` + `CycleLevel` | Done. One type, three levels, parent links, children inside parents, siblings don't overlap. |
| Phase | `CyclePhase` (`base build peak taper race recovery transition`) | Done. Set on every cycle. |
| Micro length | `MesocycleTemplate.microLengthDays` | Done. The builder already lays out 10- and 14-day micros; `TrainingCycle` allows any length. |
| Layout backwards from a race | `CycleLayoutBuilder`, `MacroTemplate` | Done. |
| Guardrails | `PlanGuardrails` + `PlanEvaluator` (+ cycle-aware rules) | Done, but one global set, tuned for 7-day weeks. |
| Preferences | `PlanPreferences` | Designed (TrainingKit design §8.1), **not built**. Training days are a plain `Set<Weekday>`. |
| Goals | `Goal`, `GoalStore` | Model only; no UI, nothing reads them. |
| Week view | `WeekView` / `WeekViewModel` | Hard-wired to 7 days (carousel, `chartRange` = −7…+13 days, `loadRange`, per-week caches keyed by `weekStart`). |

So the vocabulary the user asked for is mostly there. The new work is the **paradigm**, **availability**, the **generator**, and a **period-aware calendar view**.

## 1a. Decisions (design interview, 2026-10-12)

- **Phase is separate from the cycle hierarchy.** A phase consists of an integer number of mesocycles, for every paradigm. The micro/meso/macro structure is the calendar; the phase says what the block trains for.
- **Phase becomes paradigm-defined.** `CyclePhase` changes from a fixed enum to a named value (id + display name) so a paradigm, including new ones written in code, supplies its own phase names. No user-defined phases or paradigms in MVP5. Old stored enum values must keep decoding, and new fields are optional so the production CloudKit schema and older devices keep working.
- **Micros carry a phase and a load role.** The phase is what the block trains for; the role (`build`, `recovery`, `taper`, `race`) is how hard. A recovery micro keeps its phase. Guardrails that today read `phase == .recovery` or `.build` read the role instead.
- **Paradigm is chosen per plan.**
- **Conflicts:** when a preference conflicts with a guardrail the generator backs off and the preview lists each preference it overrode and why.
- **Running only.** Other sports remain manual planned workouts.
- **80/20 is measured by planned time in zone, per micro.**
- **Availability is stored per weekday** (the calendar revolves around weeks). **Preferred run types are stored per micro day**, several allowed per day.
- **Peak volume is asked per 7 days**; the generator scales it for other micro lengths.

## 2. Paradigm

A paradigm is plain `Codable` data, not a class hierarchy, so more can be added without new code paths:

```swift
struct TrainingParadigm: Sendable, Codable, Identifiable {
    var id: String                       // "polarized-80-20", "triphasic"
    var name: String
    var microLengthDays: Int             // 7, 10 or 14
    var mesoPattern: MesocycleTemplate   // build/recovery cadence, in micros
    var macroTemplate: (Race) -> MacroTemplate   // or a data form: phase blocks as fractions of the lead time
    var intensity: IntensityDistribution // target split over zone groups, per phase
    var hardSessions: HardSessionRules   // max per micro, min gap in days, allowed session types per phase
    var guardrailOverrides: PlanGuardrails.Overrides
    var extraRules: [ParadigmRule]       // rules only this paradigm needs
}
```

The generator asks the paradigm for the cycle layout (`microLengthDays`, `mesoPattern`, phase blocks) and for what each micro may contain. It never branches on a paradigm id.

### 80/20 (polarized)
- 7-day micros, 3:1 or 2:1 meso pattern.
- About 80% of training **time** in zones 1–2, about 20% in zones 4–5, little in zone 3. The app already computes this split (`PolarizedIntensitySplit`, the Time in Zone card, the 80th-percentile marker), so the check is a rule over data we have.
- Hard sessions: at most 2–3 per micro, never on consecutive days, a long easy run as the weekly anchor.

### Triphasic (Andrew Snow, *Run Elite*)
Phases, each made of whole mesocycles:
- **Conditioning** (optional, leading): for returning from illness or injury. Default 6 weeks, length set by the athlete. Easy runs only; starts at a percentage of the athlete's recent pre-break volume (default 50%, athlete-set) and ramps gently to 100% by the end of the phase, where base takes over.
- **Base**: any length, from the plan start to the start of structural. Slow easy running plus very short maximal sprints (about 8 s, e.g. hill sprints), which stay easy overall. Builds endurance.
- **Structural**: 6 weeks. Easy runs get faster (higher HR), sprint-type intervals get slower but longer.
- **Specific**: 6 weeks. Runs just slower than race pace, intervals just faster than race pace.
- **Taper** before the A race; days are set by the paradigm default and editable by the athlete.

Micro length is the athlete's choice: 7, 10 or 14 days. Structural and specific are fixed at **6 weeks (42 days)**: six 7-day micros or three 14-day micros. 42 isn't a multiple of 10, so with 10-day micros the phase is rounded to a whole number of micros (four, 40 days) and the preview says so.

Sessions per micro are **set by the athlete** (the wizard proposes a number from the available days and slots) and can exceed two hard sessions when there are many available days or two-a-days; the guardrails and the phase's session profile still limit what the planner accepts.

Short lead time: drop structural first; if still too short, shorten specific. Base is whatever is left, and the preview reports every compromise.

Race target for specific work comes from the race's goal pace, a target heart rate (needed for ultras and hilly courses), a perceived effort, or a prediction from fitness as the fallback.

### 80/20 (polarized)
- Phases: base, peak, taper (build kept as in today's `CyclePhase`; the paradigm lists what it uses). Default **7-day micros with a 3:1 meso pattern**; the athlete can choose 10 or 14 days, with the pattern defaulting per length.
- About 80% of planned **time** in zones 1–2 and about 20% in zones 4–5, little in zone 3, measured per micro. `PolarizedIntensitySplit`, the Time in Zone card and the 80th-percentile marker already compute this split, so the check is a rule over data we have.
- Hard sessions: capped per micro, never on consecutive days, one long easy run as the micro's anchor.

## 3. Guardrails: what's shared and what changes

**Shared by every paradigm** (the safety ceiling; load-based, so paradigm-neutral): CTL ramp, ATL/CTL ratio, TSB floor/ceiling (any day and race day), strain percentile, monotony, taper shape, minimum CTL gain per meso.

**Per paradigm** (`PlanGuardrails.Overrides` applied on top of the shared set): recovery cadence, recovery depth (`recoveryLoadFraction`), build step size, session-spacing limits.

**Removed and added:** the weekly-volume percentage cap (`maxBuildProgressionFraction`) is dropped (see 6.2) and a longest-run rule is added (no more than 10% over the longest run of the previous 4 weeks).

**New rules** a paradigm contributes: `intensityDistribution` (80/20 target share), `hardSessionSpacing`, `hardSessionsPerMicro`. These become new `PlanRule` cases so findings flow through the existing `PlanEvaluator`, the create-workout warnings and the Plan Assistant with no second warning system.

**Review: guardrails that assume a 7-day week** (to check and fix in TrainingKit before 10/14-day micros are trusted):
- `maxMicrosWithoutRecovery` counts micros, so 3 means 3 weeks at 7 days but 6 weeks at 14. Express it in days.
- `maxBuildProgressionFraction` is removed (see 6.2).
- `recoveryLoadFraction` compares total micro load, which is already length-neutral if both micros have the same length; it breaks when lengths differ. Compare per-day load.
- `maxMonotony` uses a trailing window; confirm its length is a constant, not tied to the micro.
- `maxCTLRampPerWeek` is already per 7 days; fine.
- Any rule using `Calendar` week boundaries instead of the cycle's own `dateRange` needs a check.

## 4. Availability

Availability follows the athlete's calendar, which revolves around weeks, so it is stored **per weekday**:

```swift
enum DaySlot: String, Sendable, Codable { case morning, afternoonEvening }
var runAvailability: [Weekday: Set<DaySlot>]   // absent or empty = no running that day
```

- Day selected, one slot: one run, planned at that time of day. Both slots: two-a-day is allowed, not required. Guardrails and paradigm hard-session rules still apply (never two hard runs on one day).
- When the generator lays out a micro of any length, each micro day gets a date, and that date's weekday decides whether (and when) it can hold a run. In a 10-day micro the same micro day lands on different weekdays from one micro to the next, so the generator places sessions on whichever days are available and moves hard and rest days to fit.
- Availability does not depend on the paradigm, so changing paradigm never asks the athlete to re-pick it.
- Edited in Athlete settings and pre-filled in the Create Plan wizard, where it can be overridden for that plan only. The generator uses the slot for the planned start time and ordering within a day.

## 4a. Run type per day, peak volume, key races

**Run type per day.** Each available day can carry a preferred run type:

```swift
enum RunType: String, Sendable, Codable, CaseIterable { case easy, recovery, threshold, interval, long }
var dayRunTypes: [Int: Set<RunType>]   // micro day 0..<microLengthDays; absent or empty = generator chooses (typically easy)
```

Unlike availability, preferred run types follow the **micro**, not the weekday: they describe the shape of the training cycle ("day 3 is a hard day, day 7 is the long run"), so they are keyed by micro day and tied to the paradigm's micro length. A day can list **several** acceptable types; the generator picks one that suits the phase, the previous days, and the paradigm's hard-session rules. The settings screen shows weekdays beside the micro days for 7- and 14-day micros but not for 10-day ones. Switching to a paradigm with a different micro length asks the athlete to re-pick the run types.

`SessionType` from TrainingKit design §8.1 is not in the code yet; `RunType` is its first cut (tempo, hills etc. can be added later). It maps onto the existing `IntensityCategory`: recovery = `veryLow`, easy and long = `low`, threshold and interval = `high`. The generator fills a day from library workouts of that type (MVP5-5 picks by category) and falls back to the closest match. Preferences are soft: a paradigm's hard-session rules (spacing, count per micro) can override them, and the wizard says so when it does. With two slots on a day, the type applies to the main run; the second defaults to easy or recovery.

**Peak volume.** `maxWeeklyVolume: VolumeTarget` (distance or duration) is the ceiling the ramp climbs to and stops at, per 7 days so it means the same for 10- and 14-day micros (a 14-day micro may hold twice it). The ramp from `startingWeeklyVolume` is sized so the peak lands in the last build micro before the taper. If the guardrails stop the plan reaching it, the preview says so and shows the volume it did reach.

**Key races.** Plans link to races through `Race` and `RacePriority`:
- The macrocycle's `targetRaceID` is the **primary** race; the layout is built backwards from it (already how `CycleLayoutBuilder` works), so one plan has one primary race.
- **Secondary** races inside the plan get a mini-taper (a few easier days before) and a short recovery after, without breaking the build pattern; tertiary races are treated as training sessions, with no taper.
- A race's own meso (`targetRaceID` on a meso) is used when a plan has several key races in sequence.
- The wizard lists the athlete's upcoming races to choose from, with a "new race" shortcut, and shows which ones fall in the plan window.
- Race-day TSB and taper-shape guardrails apply per key race, as `PlanEvaluator` already does for loaded races.

## 5. Calendar view: Week → MicroCycle

Introduce a displayed-period abstraction instead of renaming first:

```swift
enum DisplayPeriod { case week(start: Date), micro(TrainingCycle) }   // dateRange + dayCount
```

Resolver: for the selected date, if a **micro-level cycle** contains it, show that micro (7, 10 or 14 days); otherwise show the calendar week. Paging steps to the previous/next period of whichever kind applies, so a plan boundary is crossed cleanly.

What has to stop assuming 7 days in `WeekViewModel`: `displayedWeekStart`, `displayedWeekRange`, `chartRange(for:)` (−7…+13), `loadRange`, `activities(forWeekStarting:)`, and every cache keyed by `weekStart` (re-key by period start + length). The charts' window becomes "one period either side". The day-row timeline already renders one row per day, so it extends naturally.

Order of work: make the view model period-aware with no visible change (weeks only) → add micro resolution → rename `WeekView`/`WeekViewModel` to `MicroCycleView`/`MicroCycleViewModel` as its own mechanical PR, so the behavioural diff stays reviewable.

Header shows the cycle context: macro › meso › micro name and phase.

## 6. Planner

### 6.1 Pipeline

1. **Inputs:** paradigm, key races (primary anchors the plan), start date, availability (per weekday), preferred run types (per micro day), volume measure, starting volume, peak weekly volume, ramp, long-run cap, taper days, optional conditioning phase.
2. **Cycles:** the paradigm lays out phases as whole mesocycles, backwards from the primary race (`CycleLayoutBuilder`), and the cycles are held in memory, not saved.
3. **Volume curve:** one target per micro (6.2).
4. **Day assignment:** for each micro, each micro day gets a date; the date's weekday decides if it's available and in which slot; preferred run types pick what goes where (6.3).
5. **Workout selection and sizing:** each session gets a template chosen by content and sized to its share of the micro's target (6.4).
6. **Evaluate and adjust:** project load with the existing `DailyLoadSeries` / `FitnessMetricsCalculator`, run `PlanEvaluator` with the paradigm's guardrails, apply fixed adjustments, repeat up to N times (6.5).
7. **Preview:** proposal, remaining findings, every compromise (6.6). Nothing is saved until the athlete accepts.
8. **Commit:** cycles and `PlannedActivity` values (with `cycleID`) go in through `CycleStore` and `PlanStore`, the same data a hand-made plan uses.

### 6.2 Volume curve

- The measure is **TRIMP by default**, or distance or time, chosen per plan. The same measure is used for starting volume, peak and the ramp.
- Targets are set per micro from starting volume, the ramp, the peak (per 7 days, scaled by micro length), the micro's phase and its load role. Recovery micros step down, taper micros cut, the race micro is minimal.
- **Guardrail change:** the weekly-volume percentage cap (today `maxBuildProgressionFraction`, 10% load increase between build micros) goes away; it's not a useful rule. It is replaced by a **longest-run rule**: a long run may not exceed the longest run in the previous 4 weeks by more than 10%. The CTL ramp, ATL/CTL and TSB rules remain the load ceiling.
- If the guardrails stop the plan short of the peak, the preview shows the volume it reached.

### 6.3 Day assignment

- Hard days (`threshold`, `interval`) and the long run are placed first on available days that match the athlete's preferred run types for that micro day, then easy and recovery runs fill the rest.
- Each day's preferred run types are a set; the planner picks one that suits the phase and the paradigm's rules (spacing between hard sessions, hard sessions per micro).
- Two-a-days use the second slot for easy or recovery runs by default.
- An unavailable day gets no session. If a micro has too few available days for what the phase needs, the planner drops the least important session and reports it.

### 6.4 Workout selection and sizing

- The library is the only source: **the planner creates planned workouts from existing templates and never invents templates.**
- Templates carry no phase flag. The planner decides suitability from the template's content. A paradigm phase defines a *session profile* per run type; for now the profile is the **interval work-length range** (e.g. triphasic base: about 5–10 s sprints; structural: longer, slower intervals; specific: race-pace-relative intervals).
- A profile also gives an **intensity range as a fraction of the race target** (pace, HR or effort), e.g. specific-phase intervals at 100–105% of race pace. A step's target is resolved from the athlete's zones and settings when it has none of its own; a step that can't be resolved is ignored when matching.
- Selection is a hard filter (drop templates whose content violates the profile), then the closest fit; rotate among the best fits across micros for variety. Parameters (reps, length, distance) progress through the phase and step back on recovery micros.
- Sizing uses the existing planned-load estimator (`TRIMPPlanEstimator`) on the candidate, scaling parameters until the session meets its share of the micro's target; distance and time targets use the template's own totals.
- **Targets:** the planned workout keeps the template's structure, but the planner fills the pace/HR targets of its work steps from the phase's profile and the athlete's race target.
- **No match:** the day becomes an easy run, and the preview lists the gap ("no template with ~8 s sprints").

### 6.5 Adjust loop

Bounded: **N = 20 iterations** by default, a tunable constant. Each iteration takes the most severe remaining risk finding and applies the first adjustment that fits it, in this order, then re-evaluates:

| Finding | Adjustments, in order |
|---|---|
| CTL ramp, ATL/CTL, strain, monotony | scale down the offending micro's volume (to a floor); swap its hardest session for an easy run; deepen the following recovery micro |
| TSB too low (any day) | swap a hard session for easy; add rest day among the available days |
| Longest-run rule | shorten the long run to the limit |
| Recovery micro not recovering | reduce its volume to the recovery fraction |
| Too many micros without recovery | insert a recovery micro (shifts later micros; phases keep whole mesos) |
| Race-day TSB, taper shape | adjust taper volume |
| Paradigm rules (80/20 split, hard-session spacing or count) | swap sessions between hard and easy; move a hard session to an available day with enough gap |
| Flat plan (too little CTL gain per meso) | raise volume up to the peak, if the guardrails allow |

Anything unresolved after N iterations, or with no adjustment left, is reported in the preview, not hidden. The table and N are expected to change as tests show what works.

### 6.6 Re-planning

Mid-plan changes (injury, travel, missed weeks) regenerate **from today**: same paradigm, race and cycles, with current fitness as the new starting point. The past stays as it is, and the same preview and replace confirmation apply. Re-planning only a date range is not in MVP5.

### 6.7 Preview and commit

- Shows the cycle layout (phases, mesos, micros), the planned workouts, the projected CTL/ATL/TSB, the findings, and every compromise: preferences overridden, phases shortened, templates missing.
- **Replace:** committing replaces all planned workouts in the plan window from the start date on. The preview lists what will be removed (including manual planned workouts) first, and nothing is deleted before the athlete confirms. Completed activities and past days are never touched.
- Planned workouts are the same data as hand-made ones, so they appear in the calendar, sync to the Watch and can be edited afterwards.

## 7. Phasing

1. **Foundations (TrainingKit):** guardrail 7-day audit and fixes; `TrainingParadigm`; `PlanPreferences` with `runAvailability`; new paradigm rules.
2. **View:** period-aware view model, micro resolution, then the rename.
3. **Availability UI** in Athlete settings.
4. **Generator**, then the **wizard**.
5. **Goal management UI**, standard plans.

Steps 1 and 2 are independent and can run in parallel.

## 8. Open questions
None blocking. Still to confirm from the book when encoding the triphasic phases (MVP5-100): the exact session profiles (interval work lengths and race-target fractions) per phase.
