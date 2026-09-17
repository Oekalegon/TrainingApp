import TrainingCore

/// One named heart-rate zone's bpm range under the athlete's currently-effective zone settings —
/// see ``AthleteViewModel/heartRateZoneRanges``.
public struct HeartRateZoneRange: Identifiable, Hashable {
    public var id: HeartRateZone { zone }
    public let zone: HeartRateZone
    /// This zone's heart-rate range in bpm, from ``HeartRateZoneModel/zoneBPMRange(_:)``.
    public let bpmRange: ClosedRange<Double>
}
