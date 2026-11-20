import Foundation
import TrainingCore

/// The athlete's heart-rate zones as the watch needs them (WATCH-102): the settings in effect
/// today, from which it works out each zone's bpm range and which zone a heart rate is in.
///
/// The settings travel as they are, not as precomputed bpm ranges, so the watch uses
/// ``HeartRateZoneModel`` exactly as the phone does and the two can't disagree about a boundary,
/// whichever zone method (Karvonen, percentage of max, lactate threshold) the athlete chose.
public struct WatchZones: Sendable, Codable, Hashable {
    /// The settings the zones come from.
    public var settings: HeartRateZoneSettings

    /// Creates the zones from the athlete's current heart-rate settings.
    public init(settings: HeartRateZoneSettings) {
        self.settings = settings
    }

    /// The heart-rate range of `zone` (1 to 5) in bpm, or `nil` for a zone outside that range or
    /// when the zone method can't give one (lactate threshold without a threshold set).
    public func bpmRange(of zone: Int) -> ClosedRange<Double>? {
        HeartRateZoneModel(settings: settings).zoneBPMRange(zone)
    }

    /// The zone a heart rate is in: 0 below zone 1, 1 to 5, and 5 above the top of zone 5.
    /// `nil` when the zone boundaries can't be worked out (see ``bpmRange(of:)``).
    ///
    /// A heart rate between two zones' ranges (the lactate threshold method can leave gaps) counts
    /// as the lower zone.
    ///
    /// - Parameter bpm: The heart rate in beats per minute.
    public func zone(forHeartRate bpm: Double) -> Int? {
        let model = HeartRateZoneModel(settings: settings)
        let ranges = (1...5).compactMap { zone in model.zoneBPMRange(zone).map { (zone: zone, range: $0) } }
        guard ranges.count == 5 else { return nil }
        guard let lowest = ranges.first, bpm >= lowest.range.lowerBound else { return 0 }
        return ranges.last { bpm >= $0.range.lowerBound }?.zone ?? 0
    }
}
