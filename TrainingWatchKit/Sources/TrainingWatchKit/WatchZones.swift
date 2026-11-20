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
    /// Builds ``ZoneBands`` on each call; where this runs often (the watch's run screen), keep a
    /// ``ZoneBands`` and ask that.
    ///
    /// - Parameter bpm: The heart rate in beats per minute.
    public func zone(forHeartRate bpm: Double) -> Int? {
        ZoneBands(zones: self)?.zone(forHeartRate: bpm)
    }
}

/// The five zones' bpm ranges, worked out once, for asking which zone a heart rate is in without
/// rebuilding the model for every reading (WATCH-102).
public struct ZoneBands: Sendable, Hashable {
    private let ranges: [ClosedRange<Double>]

    /// The bands of `zones`, or `nil` when the zone method can't give all five (lactate threshold
    /// without a threshold set).
    public init?(zones: WatchZones) {
        let model = HeartRateZoneModel(settings: zones.settings)
        let ranges = (1...5).compactMap { model.zoneBPMRange($0) }
        guard ranges.count == 5 else { return nil }
        self.ranges = ranges
    }

    /// The heart-rate range of `zone` (1 to 5) in bpm, or `nil` for any other number.
    public func range(of zone: Int) -> ClosedRange<Double>? {
        (1...5).contains(zone) ? ranges[zone - 1] : nil
    }

    /// The zone a heart rate is in: 0 below zone 1, 1 to 5, and 5 above the top of zone 5. A heart
    /// rate between two zones' ranges (the lactate threshold method can leave gaps) counts as the
    /// lower zone.
    public func zone(forHeartRate bpm: Double) -> Int {
        guard bpm >= ranges[0].lowerBound else { return 0 }
        return (ranges.lastIndex { bpm >= $0.lowerBound } ?? 0) + 1
    }
}
