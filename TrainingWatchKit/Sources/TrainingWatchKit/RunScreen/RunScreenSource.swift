import Foundation
import TrainingCore

/// What a run screen reads to draw itself (WATCH-138): the run's readings and statistics. ``RunRecorder`` is the
/// source on the watch; the iPhone editor draws the same screens from sample values (`SampleRunScreenSource` in
/// `TrainingAppKit`), so the preview and the watch can't drift apart.
@MainActor
public protocol RunScreenSource: AnyObject {
    var stepEngine: WorkoutStepEngine? { get }
    var stats: RunStatsTracker { get }
    var spans: RunSpans { get }
    var heartRate: Double? { get }
    var distanceMeters: Double { get }
    var averageSecondsPerMeter: Double? { get }
    /// The pace to count a distance at, for the battery forecast.
    var secondsPerMeter: Double { get }
    var zoneTimeFractions: [Double]? { get }
    var secondsInCurrentZone: Double? { get }
    var secondsSinceEnteringZone: Double? { get }
    /// Whether the run is paused, which VoiceOver says with the time.
    var isPaused: Bool { get }
    var batteryReadings: [BatteryForecast.Reading] { get }
    /// The athlete's heart-rate zones, or `nil` while there are none.
    var zoneBands: ZoneBands? { get }

    func elapsed(at date: Date) -> TimeInterval
    func currentSecondsPerMeter(at date: Date) -> Double?
    func stepProgress(at date: Date) -> StepProgress?
    func spanMark(at date: Date) -> RunSpans.Mark
    func reading(_ quantity: RunQuantity, _ statistic: RunStatistic, _ scope: RunScope, at date: Date) -> Double?
    /// The watch's battery now.
    func battery(at date: Date) -> BatteryDisplay
}

extension RunRecorder: RunScreenSource {
    public var isPaused: Bool { phase == .paused }
    public var zoneBands: ZoneBands? { zoneStore?.bands }
    public func battery(at date: Date) -> BatteryDisplay { backend.battery(elapsed: elapsed(at: date)) }
}
