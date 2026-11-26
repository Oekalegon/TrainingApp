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
        // The level moves in coarse steps, so no drop is not no drain: it counts as half the typical one.
        let forecast = BatteryForecast(readings: readings([(0, 0.90), (900, 0.90)]))
        #expect(abs(forecast.drainPerHour - BatteryForecast.typicalDrainPerHour / 2) < 0.001)
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

    @Test("the pace for an estimate follows the average and keeps the current one within half to double of it")
    func estimatePace() {
        #expect(RemainingEstimate.estimatePace(current: 0.3, average: 0.3) == 0.3)
        #expect(RemainingEstimate.estimatePace(current: 2.0, average: 0.3) == 0.6)
        #expect(RemainingEstimate.estimatePace(current: 0.05, average: 0.3) == 0.15)
        #expect(RemainingEstimate.estimatePace(current: nil, average: 0.3) == 0.3)
        #expect(RemainingEstimate.estimatePace(current: 0.4, average: nil) == 0.4)
        #expect(RemainingEstimate.estimatePace(current: nil, average: nil) == 0.36)
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

    private let battery = BatteryDisplay(level: 0.8, isCharging: false)

    @Test("an open step is counted by the duration of earlier runs, less what has been run")
    func openStepUsesTypicalDuration() throws {
        let open = RemainingEstimate(seconds: 600, isComplete: false)
        // Earlier runs took 2 hours, 1 hour is done: 1 hour left at 12% an hour -> 68%.
        let result = try #require(BatteryProjection(
            battery: battery, readings: [], remaining: open, elapsed: 3600, typicalDuration: 7200))
        #expect(result.text == "~68% AT END")
        // Never less than the steps known to be left.
        let long = RemainingEstimate(seconds: 7200, isComplete: false)
        let floor = try #require(BatteryProjection(
            battery: battery, readings: [], remaining: long, elapsed: 3600, typicalDuration: 3700))
        #expect(floor.text == "~56% AT END")
    }

    @Test("the athlete's own drain replaces the typical one until the run has shown its own")
    func ownDrain() throws {
        let remaining = RemainingEstimate(seconds: 3600, isComplete: true)
        let result = try #require(BatteryProjection(
            battery: battery, readings: [], remaining: remaining, drainPerHour: 0.2))
        #expect(result.text == "~60% AT END")
        let rough = try #require(BatteryProjection(
            battery: battery, readings: [], remaining: remaining, drainPerHour: 0.2, isRough: true))
        #expect(rough.spoken == "about 60 percent at the end, a rough estimate")
    }
}

@Suite("Battery metadata (WATCH-119)")
struct BatteryMetadataTests {
    @Test("the first and last reading become the start and end level")
    func startAndEnd() throws {
        let readings = [
            BatteryForecast.Reading(time: 0, level: 0.9),
            BatteryForecast.Reading(time: 1800, level: 0.8),
            BatteryForecast.Reading(time: 3600, level: 0.7)
        ]
        let metadata = try #require(WorkoutMetadata.battery(readings: readings))
        #expect(metadata[WorkoutMetadata.batteryStart] as? Double == 0.9)
        #expect(metadata[WorkoutMetadata.batteryEnd] as? Double == 0.7)
    }

    @Test("too few readings give no metadata")
    func tooFew() {
        #expect(WorkoutMetadata.battery(readings: []) == nil)
        #expect(WorkoutMetadata.battery(readings: [.init(time: 0, level: 0.9)]) == nil)
    }
}

@Suite("BatteryDrainHistory (WATCH-119)")
struct BatteryDrainHistoryTests {
    private func run(from start: Double, to end: Double, hours: Double = 1) -> [BatteryForecast.Reading] {
        [.init(time: 0, level: start), .init(time: hours * 3600, level: end)]
    }

    private let normal = BatteryDrainFactors()
    private let lowPower = BatteryDrainFactors(lowPowerMode: true)

    private func history(_ drops: [(Double, BatteryDrainFactors)]) -> BatteryDrainHistory {
        var history = BatteryDrainHistory()
        for (drop, factors) in drops { history.add(readings: run(from: 0.9, to: 0.9 - drop), factors: factors) }
        return history
    }

    @Test("a run's drain is its drop over its time; short runs, flat runs and charging give none")
    func drainOfRun() {
        #expect(abs(BatteryDrainHistory.drain(of: run(from: 0.9, to: 0.78))! - 0.12) < 1e-9)
        #expect(BatteryDrainHistory.drain(of: run(from: 0.9, to: 0.6, hours: 0.1)) == nil)
        #expect(BatteryDrainHistory.drain(of: run(from: 0.9, to: 0.895)) == nil)
        #expect(BatteryDrainHistory.drain(of: run(from: 0.5, to: 0.8)) == nil)
        #expect(BatteryDrainHistory.drain(of: []) == nil)
    }

    @Test("the estimate is the median and needs two runs")
    func median() throws {
        #expect(history([(0.1, normal)]).estimate(for: normal) == nil)
        #expect(abs(try #require(history([(0.1, normal), (0.2, normal)]).estimate(for: normal)).drainPerHour - 0.15) < 1e-9)
        let three = try #require(history([(0.1, normal), (0.2, normal), (0.4, normal)]).estimate(for: normal))
        #expect(abs(three.drainPerHour - 0.2) < 1e-9)
    }

    @Test("runs with the same factors are used when there are enough, and all runs, less sure, otherwise")
    func factors() throws {
        let mixed = history([(0.1, normal), (0.1, normal), (0.3, lowPower), (0.3, lowPower)])
        let same = try #require(mixed.estimate(for: lowPower))
        #expect(abs(same.drainPerHour - 0.3) < 1e-9)
        let other = try #require(mixed.estimate(for: BatteryDrainFactors(speakerSound: true)))
        #expect(abs(other.drainPerHour - 0.2) < 1e-9)
        #expect(other.confidence == .low)
    }

    @Test("confidence grows with the number of alike runs and shrinks with their spread")
    func confidence() throws {
        let steady = history(Array(repeating: (0.12, normal), count: 5))
        #expect(try #require(steady.estimate(for: normal)).confidence == .high)
        let few = history([(0.12, normal), (0.12, normal)])
        #expect(try #require(few.estimate(for: normal)).confidence == .low)
        let wild = history([(0.05, normal), (0.12, normal), (0.3, normal), (0.1, normal), (0.2, normal)])
        #expect(try #require(wild.estimate(for: normal)).confidence == .low)
    }

    @Test("only the last ten runs are kept")
    func capacity() {
        let many = history(Array(repeating: (0.1, normal), count: 15))
        #expect(many.runs.count == BatteryDrainHistory.capacity)
    }

    @Test("the store keeps the history between launches")
    func store() throws {
        let defaults = try #require(UserDefaults(suiteName: "BatteryDrainStoreTests-\(UUID().uuidString)"))
        BatteryDrainStore(defaults: defaults).record(readings: run(from: 0.9, to: 0.8), factors: normal)
        BatteryDrainStore(defaults: defaults).record(readings: run(from: 0.9, to: 0.7), factors: lowPower)
        #expect(BatteryDrainStore(defaults: defaults).load().runs.count == 2)
    }
}
