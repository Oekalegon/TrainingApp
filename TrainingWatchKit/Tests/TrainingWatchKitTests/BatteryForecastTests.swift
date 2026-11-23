import Foundation
import Testing
import TrainingCore
@testable import TrainingWatchKit

@Suite("BatteryForecast (WATCH-119)")
struct BatteryForecastTests {
    private func readings(_ points: [(Double, Double)]) -> [BatteryForecast.Reading] {
        points.map { BatteryForecast.Reading(time: $0.0, level: $0.1) }
    }

    @Test("without readings, or with one, the typical drain is used")
    func prior() {
        #expect(BatteryForecast(readings: []).drainPerHour == BatteryForecast.typicalDrainPerHour)
        #expect(BatteryForecast(readings: readings([(0, 0.9)])).drainPerHour == BatteryForecast.typicalDrainPerHour)
        #expect(BatteryForecast(readings: readings([(0, 0.9)]), prior: 0.2).drainPerHour == 0.2)
    }

    @Test("a short stretch is not measured: the level moves in coarse steps")
    func tooShort() {
        // 2 minutes and a 1% drop would be 30% an hour.
        let forecast = BatteryForecast(readings: readings([(0, 0.90), (120, 0.89)]))
        #expect(forecast.drainPerHour == BatteryForecast.typicalDrainPerHour)
    }

    @Test("a long enough measurement counts fully: 20 minutes of 6% is 18% an hour")
    func measured() {
        let forecast = BatteryForecast(readings: readings([(0, 0.90), (600, 0.87), (1200, 0.84)]))
        #expect(abs(forecast.drainPerHour - 0.18) < 0.001)
    }

    @Test("a measurement is blended with the typical drain until it has run for 15 minutes")
    func blended() {
        // 10 minutes and 3%: measured 18% an hour, with two thirds of the trust.
        let forecast = BatteryForecast(readings: readings([(0, 0.90), (600, 0.87)]))
        let expected = (1.0 / 3) * BatteryForecast.typicalDrainPerHour + (2.0 / 3) * 0.18
        #expect(abs(forecast.drainPerHour - expected) < 0.001)
    }

    @Test("only the last 20 minutes count")
    func window() {
        // An hour with a fast start, then 15 minutes of 1.5%: the window sees only the slow part.
        let forecast = BatteryForecast(readings: readings([(0, 1.0), (2700, 0.70), (3600, 0.685)]))
        #expect(forecast.drainPerHour < 0.12)
    }

    @Test("a long run with no drop at all is an answer: a small drain")
    func flat() {
        let forecast = BatteryForecast(readings: readings([(0, 0.90), (900, 0.90)]))
        #expect(forecast.drainPerHour < 0.1)
        #expect(forecast.drainPerHour > 0)
    }

    @Test("a rising level (a charger, or a reset) is not a measurement")
    func rising() {
        let forecast = BatteryForecast(readings: readings([(0, 0.50), (1200, 0.60)]))
        #expect(forecast.drainPerHour == BatteryForecast.typicalDrainPerHour)
    }

    @Test("the charge after the rest of the workout, and when it runs out")
    func levels() {
        let forecast = BatteryForecast(readings: readings([(0, 0.90), (600, 0.87), (1200, 0.84)]))
        #expect(abs(forecast.level(after: 3600, from: 0.80) - 0.62) < 0.001)
        #expect(forecast.level(after: 6 * 3600, from: 0.5) < 0)
        #expect(abs(forecast.timeUntilEmpty(from: 0.36) - 2 * 3600) < 1)
        #expect(forecast.level(after: -50, from: 0.5) == 0.5)
    }

    @Test("green from 20%, yellow from 10%, orange above 0 and red when it runs out, with a 3% margin")
    func verdicts() {
        let forecast = BatteryForecast(readings: [])
        #expect(forecast.verdict(endLevel: 0.30) == .enough)
        #expect(forecast.verdict(endLevel: 0.23) == .enough)
        #expect(forecast.verdict(endLevel: 0.22) == .tight)
        #expect(forecast.verdict(endLevel: 0.13) == .tight)
        #expect(forecast.verdict(endLevel: 0.12) == .critical)
        #expect(forecast.verdict(endLevel: 0.03) == .critical)
        #expect(forecast.verdict(endLevel: 0.02) == .runsOut)
        #expect(forecast.verdict(endLevel: -0.4) == .runsOut)
    }

    @Test("what is left of a workout: the current step and every step after it")
    func remaining() throws {
        // 60 s warm-up, 2 x (90 s work, 90 s recover), 1 km cool-down.
        let engine = WorkoutStepEngine(blocks: [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(60))]),
            WorkoutBlock(steps: [
                WorkoutStep(kind: .work, goal: .time(90)), WorkoutStep(kind: .recovery, goal: .time(90))
            ], repetitions: 2),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .distance(1000))])
        ])
        let progress = engine.progress(elapsed: 20, distance: 0)
        // 40 s of the warm-up, 360 s of intervals, and 1 km at 0.36 s per metre.
        let estimate = try #require(engine.remaining(progress: progress, secondsPerMeter: 0.36))
        #expect(abs(estimate.seconds - (40 + 360 + 360)) < 0.001)
        #expect(estimate.isComplete)
    }

    @Test("an open step can't be counted, so the estimate is incomplete; a finished workout has none")
    func remainingOpen() throws {
        let engine = WorkoutStepEngine(blocks: [
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(60))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .open)])
        ])
        let estimate = try #require(engine.remaining(progress: engine.progress(elapsed: 10, distance: 0), secondsPerMeter: 0.36))
        #expect(abs(estimate.seconds - 50) < 0.001)
        #expect(!estimate.isComplete)
        var finished = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(5))])])
        _ = finished.update(elapsed: 10, distance: 0)
        #expect(finished.remaining(progress: nil, secondsPerMeter: 0.36) == nil)
    }
}

@Suite("BatteryProjection (WATCH-119)")
struct BatteryProjectionTests {
    private func projection(
        level: Float, charging: Bool = false, seconds: TimeInterval, complete: Bool = true
    ) -> BatteryProjection? {
        BatteryProjection(
            battery: BatteryDisplay(level: level, isCharging: charging), readings: [],
            remaining: RemainingEstimate(seconds: seconds, isComplete: complete))
    }

    @Test("enough: the end charge as a percentage, in green")
    func enough() throws {
        // 80% now, 1 hour at the typical 12% an hour: 68%.
        let result = try #require(projection(level: 0.8, seconds: 3600))
        #expect(result.text == "~68% AT END")
        #expect(result.verdict == .enough)
        #expect(result.spoken == "about 68 percent at the end")
    }

    @Test("tight and critical")
    func tightAndCritical() throws {
        // 30% now, 1 hour 30 minutes at 12% an hour: 12%, which with the margin is critical.
        #expect(try #require(projection(level: 0.3, seconds: 5400)).verdict == .critical)
        // 30% now, 1 hour: 18%, which is tight.
        #expect(try #require(projection(level: 0.3, seconds: 3600)).verdict == .tight)
    }

    @Test("it runs out: the time until it is empty instead of the end charge")
    func runsOut() throws {
        // 30% now at 12% an hour lasts 2 hours 30 minutes; the workout is 4 hours.
        let result = try #require(projection(level: 0.3, seconds: 4 * 3600))
        #expect(result.text == "EMPTY IN 2:30")
        #expect(result.verdict == .runsOut)
        #expect(result.spoken == "battery will run out in 2 hours 30 minutes")
    }

    @Test("no projection while charging, with an unknown level, an open step or no workout")
    func none() {
        #expect(projection(level: 0.8, charging: true, seconds: 3600) == nil)
        #expect(projection(level: -1, seconds: 3600) == nil)
        #expect(projection(level: 0.8, seconds: 3600, complete: false) == nil)
        #expect(BatteryProjection(battery: BatteryDisplay(level: 0.8, isCharging: false), readings: [], remaining: nil) == nil)
    }
}
