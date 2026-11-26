import Foundation
import TrainingCore
import TrainingWatchKit

/// Made-up readings for the preview of a run screen in the editor (WATCH-138): a run 25 minutes in, 4.3 km, heart
/// rate in zone 3, and for a workout, the fifth interval of six at a pace target, so every item has something to show.
/// A snapshot, not a clock: nothing moves, so the preview holds still while the athlete edits.
@MainActor
public final class SampleRunScreenSource: RunScreenSource {
    /// The run's time in the sample, in seconds.
    public static let sampleElapsed: TimeInterval = 25 * 60 + 30
    /// A run at about 5:50 a kilometre.
    private static let metersPerSecond = 2.85

    public private(set) var stepEngine: WorkoutStepEngine?
    public private(set) var stats = RunStatsTracker()
    public private(set) var spans = RunSpans()
    public let statistics: RunStatisticsBook
    public let isWorkout: Bool

    public private(set) var heartRate: Double?
    public let distanceMeters = SampleRunScreenSource.sampleElapsed * SampleRunScreenSource.metersPerSecond
    public let averageSecondsPerMeter: Double? = 1 / SampleRunScreenSource.metersPerSecond
    public let secondsPerMeter = 1 / SampleRunScreenSource.metersPerSecond
    public let zoneTimeFractions: [Double]? = [0.02, 0.1, 0.46, 0.28, 0.12, 0.02]
    public let secondsInCurrentZone: Double? = 11 * 60 + 40
    public let secondsSinceEnteringZone: Double? = 3 * 60 + 5
    public let isPaused = false
    public let batteryReadings: [BatteryForecast.Reading] = [
        .init(time: 0, level: 0.80), .init(time: 600, level: 0.77), .init(time: 1200, level: 0.74), .init(time: 1500, level: 0.73),
    ]
    public let zoneBands: ZoneBands? = ZoneBands(
        zones: WatchZones(settings: .init(effectiveDate: .distantPast, restingHeartRateBPM: 55, maxHeartRateBPM: 190)))

    /// - Parameter isWorkout: Whether the sample run is a planned workout (with steps and a pace target) or a free run.
    public init(isWorkout: Bool) {
        self.isWorkout = isWorkout
        var engine = isWorkout ? Self.makeEngine() : nil
        var book = RunStatisticsBook()
        var stats = RunStatsTracker()
        var spans = RunSpans()
        var lastHeartRate: Double?
        let splitLength = 1000.0
        // Play the first 25 minutes through at 5-second steps, so the statistics of every scope have something in them.
        for second in stride(from: 5, through: Int(Self.sampleElapsed), by: 5) {
            let time = Double(second)
            let distance = time * Self.metersPerSecond
            _ = engine?.update(elapsed: time, distance: distance)
            let stepKey = engine?.current?.index
            let splitKey = Int(distance / splitLength)
            let wave = sin(time / 90 * 2 * .pi)
            let climb = max(0, wave) * 0.4
            // One heart rate for the run's figures and for the statistics of every scope, as the recorder does.
            let bpm = 146 + 12 * sin(time / 200 * 2 * .pi)
            stats.add(heartRate: bpm)
            lastHeartRate = bpm
            stats.add(altitude: 12 + time / 40 + 5 * sin(time / 150), atDistance: distance)
            book.add(.heartRate, bpm, stepKey: stepKey, splitKey: splitKey)
            book.add(.pace, Self.metersPerSecond + 0.3 * wave, stepKey: stepKey, splitKey: splitKey)
            for (quantity, value) in SimulatedReadings.values(atElapsed: time) {
                book.add(quantity, value, stepKey: stepKey, splitKey: splitKey)
            }
            spans.update(
                .init(elapsed: time, distance: distance, climb: stats.elevationGain + climb),
                stepKey: stepKey, splitKey: splitKey, splitLength: splitLength, secondsPerMeter: 1 / Self.metersPerSecond)
        }
        self.stepEngine = engine
        self.heartRate = lastHeartRate.map { $0.rounded() }
        self.stats = stats
        self.spans = spans
        statistics = book
    }

    /// Six rounds of 4 minutes at a pace target and 2 minutes easy, with a warm-up first: at 25:30 the run is in the
    /// fourth round's work step.
    private static func makeEngine() -> WorkoutStepEngine {
        WorkoutStepEngine(blocks: [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(300), target: .heartRateZone(2))]),
            WorkoutBlock(
                steps: [
                    WorkoutStep(kind: .work, goal: .time(240), target: .heartRateZone(4), companionTarget: .pace(330...350)),
                    WorkoutStep(kind: .recovery, goal: .time(120), target: .heartRateZone(2)),
                ],
                repetitions: 6),
        ])
    }

    public func elapsed(at date: Date) -> TimeInterval { Self.sampleElapsed }

    public func currentSecondsPerMeter(at date: Date) -> Double? { 1 / (Self.metersPerSecond + 0.1) }

    public func stepProgress(at date: Date) -> StepProgress? {
        stepEngine?.progress(elapsed: Self.sampleElapsed, distance: distanceMeters)
    }

    public func spanMark(at date: Date) -> RunSpans.Mark {
        RunSpans.Mark(elapsed: Self.sampleElapsed, distance: distanceMeters, climb: stats.elevationGain)
    }

    public func battery(at date: Date) -> BatteryDisplay { BatteryDisplay(level: 0.73, isCharging: false) }
}
