import Foundation
import Testing
import TrainingCore
@testable import TrainingWatchKit

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func at(day: Int, hour: Int = 8) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
}

private func workout(_ name: String = "Steady") -> StructuredWorkout {
    StructuredWorkout(
        name: name, sport: .running,
        blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])])
}

private func planned(_ day: Int, hour: Int = 8, name: String = "Steady") -> WatchPlannedWorkout {
    WatchPlannedWorkout(id: UUID(), date: at(day: day, hour: hour), workout: workout(name))
}

@Suite("WatchPlan (WATCH-103)")
struct WatchPlanTests {
    @Test("workouts are kept earliest first")
    func sorted() {
        let later = planned(22), earlier = planned(20), sameDayLater = planned(20, hour: 17)
        #expect(WatchPlan(workouts: [later, sameDayLater, earlier]).workouts == [earlier, sameDayLater, later])
    }

    @Test("a day's workouts are the ones planned on that calendar day, in the given calendar")
    func workoutsOnDay() {
        let today = planned(20, hour: 7), tonight = planned(20, hour: 23), tomorrow = planned(21, hour: 0)
        let plan = WatchPlan(workouts: [today, tonight, tomorrow])
        #expect(plan.workouts(on: at(day: 20, hour: 12), calendar: utc) == [today, tonight])
        #expect(plan.workouts(on: at(day: 21, hour: 12), calendar: utc) == [tomorrow])
        #expect(plan.workouts(on: at(day: 25), calendar: utc).isEmpty)
    }

    @Test("a plan with steps survives the trip through an application context, together with the zones")
    func contextRoundTrip() throws {
        let zones = WatchZones(settings: HeartRateZoneSettings(
            effectiveDate: Date(timeIntervalSince1970: 0), restingHeartRateBPM: 50, maxHeartRateBPM: 190))
        let context = WatchContext(zones: zones, plan: WatchPlan(workouts: [planned(20)]))
        #expect(WatchContext(applicationContext: try context.applicationContext()) == context)
    }

    @Test("a context with only one of the two keeps the other empty, and bad contexts give none")
    func partialAndBadContexts() throws {
        let onlyPlan = WatchContext(plan: WatchPlan(workouts: []))
        let decoded = try #require(WatchContext(applicationContext: try onlyPlan.applicationContext()))
        #expect(decoded.zones == nil)
        #expect(decoded.plan == WatchPlan(workouts: []))
        #expect(WatchContext(applicationContext: [:]) == nil)
        #expect(WatchContext(applicationContext: ["watchContext.v1": Data("not json".utf8)]) == nil)
        #expect(WatchContext(applicationContext: ["watchContext.v1": "text"]) == nil)
    }
}

@MainActor
@Suite("WatchPlanStore (WATCH-103)")
struct WatchPlanStoreTests {
    private func freshDefaults() -> UserDefaults {
        let name = "WatchPlanStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("a new store has no plan until one arrives, which is different from an empty plan")
    func startsEmpty() {
        let store = WatchPlanStore(cache: WatchPlanCache(defaults: freshDefaults()))
        #expect(store.plan == nil)
        #expect(store.today(asOf: at(day: 20), calendar: utc).isEmpty)
        store.update(WatchPlan(workouts: []))
        #expect(store.plan == WatchPlan(workouts: []))
    }

    @Test("a received plan is used, is still there at the next launch, and is replaced by a newer one")
    func keepsAndReplaces() {
        let defaults = freshDefaults()
        let store = WatchPlanStore(cache: WatchPlanCache(defaults: defaults))
        let first = WatchPlan(workouts: [planned(20)])
        store.update(first)
        #expect(WatchPlanStore(cache: WatchPlanCache(defaults: defaults)).plan == first)
        let second = WatchPlan(workouts: [planned(21)])
        store.update(second)
        #expect(WatchPlanStore(cache: WatchPlanCache(defaults: defaults)).plan == second)
    }

    @Test("a plan used without persisting is gone at the next launch")
    func notPersisted() {
        let defaults = freshDefaults()
        WatchPlanStore(cache: WatchPlanCache(defaults: defaults)).update(WatchPlan(workouts: [planned(20)]), persist: false)
        #expect(WatchPlanStore(cache: WatchPlanCache(defaults: defaults)).plan == nil)
    }

    @Test("today's workouts come from the plan, for the day given")
    func today() {
        let store = WatchPlanStore(cache: WatchPlanCache(defaults: freshDefaults()))
        let todays = planned(20), other = planned(22)
        store.update(WatchPlan(workouts: [todays, other]))
        #expect(store.today(asOf: at(day: 20, hour: 15), calendar: utc) == [todays])
        #expect(store.today(asOf: at(day: 21), calendar: utc).isEmpty)
    }
}

@Suite("WatchWorkoutSummary (WATCH-103)")
struct WatchWorkoutSummaryTests {
    private let metric = Locale(identifier: "en_GB_u_ms_metric")
    private let imperial = Locale(identifier: "en_US")

    private func workout(_ blocks: [WorkoutBlock]) -> StructuredWorkout {
        StructuredWorkout(name: "Test", sport: .running, blocks: blocks)
    }

    @Test("a steady run reads as its duration and zone")
    func steady() {
        let lines = WatchWorkoutSummary.lines(for: workout([
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(2700), target: .heartRateZone(2))])
        ]), locale: metric)
        #expect(lines == ["45 min Z2"])
    }

    @Test("warm-up and cool-down are named, and a repeated block shows its repetitions")
    func intervals() {
        let lines = WatchWorkoutSummary.lines(for: workout([
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(600), target: .heartRateZone(1))]),
            WorkoutBlock(steps: [
                WorkoutStep(kind: .work, goal: .time(180), target: .heartRateZone(4)),
                WorkoutStep(kind: .recovery, goal: .time(120), target: .heartRateZone(2))
            ], repetitions: 4),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(300), target: .heartRateZone(1))])
        ]), locale: metric)
        #expect(lines == ["Warm-up 10 min Z1", "4 × (3 min Z4, Recovery 2 min Z2)", "Cool-down 5 min Z1"])
    }

    @Test("durations use hours, minutes and seconds")
    func durations() {
        func text(_ seconds: TimeInterval) -> String { WatchWorkoutSummary.goalText(.time(seconds), locale: metric) }
        #expect(text(45) == "45 s")
        #expect(text(150) == "2 min 30 s")
        #expect(text(3900) == "1 h 5 min")
        #expect(text(0) == "0 s")
    }

    @Test("distances follow the locale's measurement system")
    func distances() {
        #expect(WatchWorkoutSummary.goalText(.distance(400), locale: metric) == "400 m")
        #expect(WatchWorkoutSummary.goalText(.distance(1500), locale: metric) == "1.5 km")
        #expect(WatchWorkoutSummary.goalText(.distance(10000), locale: metric) == "10 km")
        #expect(WatchWorkoutSummary.goalText(.distance(1609.344), locale: imperial) == "1 mi")
        #expect(WatchWorkoutSummary.goalText(.open, locale: metric) == "Open")
    }

    @Test("zone ranges, bpm ranges and RPE read as targets")
    func targets() {
        func line(_ target: IntensityTarget?, companion: IntensityTarget? = nil) -> String {
            WatchWorkoutSummary.stepText(
                WorkoutStep(kind: .work, goal: .time(60), target: target, companionTarget: companion), locale: metric)
        }
        #expect(line(.heartRateZoneRange(3.0...4.0)) == "1 min Z3")
        #expect(line(.heartRateZoneRange(3.0...3.4)) == "1 min Z3.0-3.4")
        #expect(line(.heartRateRange(150.2, 160.4)) == "1 min 150-160 bpm")
        #expect(line(.rpe(6)) == "1 min RPE 6")
        #expect(line(nil) == "1 min")
    }

    @Test("a pace step takes its heart-rate companion as the target")
    func companion() {
        let step = WorkoutStep(kind: .work, goal: .time(60), target: .pace(5.0...5.5), companionTarget: .heartRateZone(3))
        #expect(WatchWorkoutSummary.heartRateTarget(of: step) == .heartRateZone(3))
        #expect(WatchWorkoutSummary.stepText(step, locale: metric) == "1 min Z3")
        let paceOnly = WorkoutStep(kind: .work, goal: .time(60), target: .pace(5.0...5.5))
        #expect(WatchWorkoutSummary.heartRateTarget(of: paceOnly) == nil)
    }
}
