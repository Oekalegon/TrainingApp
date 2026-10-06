import Foundation
import TrainingCore

/// What the athlete types into the heart-rate settings sheet (MVP2-132): the date the settings take
/// effect, resting and maximum heart rate, an optional lactate threshold, and the zone method. Checks
/// the values and builds the ``HeartRateZoneSettings`` to record.
struct HeartRateSettingsDraft: Equatable {
    /// The first day the settings apply.
    var effectiveDate: Date
    var restingHeartRate: Int
    var maxHeartRate: Int
    /// `nil` while no lactate threshold is set.
    var lactateThresholdHeartRate: Int?
    var zoneMethod: HeartRateZoneMethod
    /// The maximum the draft started from and where it came from, so leaving it untouched keeps its
    /// source (a workout-measured max stays one) and changing it makes it the athlete's own.
    private let originalMax: Int
    private let originalSource: MaxHeartRateSource

    /// Starts from `settings` (the entry in effect on the date, or the current one), or from typical
    /// values when there are none.
    ///
    /// - Parameters:
    ///   - settings: The entry to prefill from, if any.
    ///   - effectiveDate: The date the new entry would take effect.
    init(prefilling settings: HeartRateZoneSettings?, effectiveDate: Date) {
        self.effectiveDate = effectiveDate
        restingHeartRate = Int((settings?.restingHeartRateBPM ?? 55).rounded())
        maxHeartRate = Int((settings?.maxHeartRateBPM ?? 185).rounded())
        lactateThresholdHeartRate = settings?.lactateThresholdHeartRateBPM.map { Int($0.rounded()) }
        zoneMethod = settings?.zoneMethod ?? .karvonen
        originalMax = maxHeartRate
        originalSource = settings?.maxHeartRateSource ?? .manual
    }

    /// Why the values can't be saved, or `nil` when they can.
    var validationMessage: String? {
        guard (25...120).contains(restingHeartRate) else { return "Resting heart rate should be between 25 and 120 bpm." }
        guard (100...230).contains(maxHeartRate) else { return "Maximum heart rate should be between 100 and 230 bpm." }
        guard maxHeartRate >= restingHeartRate + 20 else {
            return "Maximum heart rate should be at least 20 bpm above the resting heart rate."
        }
        if let lactateThresholdHeartRate {
            guard lactateThresholdHeartRate > restingHeartRate, lactateThresholdHeartRate <= maxHeartRate else {
                return "Lactate threshold should be above the resting and no higher than the maximum heart rate."
            }
        } else if zoneMethod == .lactateThreshold {
            return "Enter a lactate threshold heart rate to use this zone method."
        }
        return nil
    }

    /// The settings to record: the athlete's own maximum (``MaxHeartRateSource/manual``) when they
    /// changed it, the original's source when they didn't.
    func settings() -> HeartRateZoneSettings {
        HeartRateZoneSettings(
            effectiveDate: effectiveDate,
            restingHeartRateBPM: Double(restingHeartRate),
            maxHeartRateBPM: Double(maxHeartRate),
            maxHeartRateSource: maxHeartRate == originalMax ? originalSource : .manual,
            lactateThresholdHeartRateBPM: lactateThresholdHeartRate.map(Double.init),
            zoneMethod: zoneMethod
        )
    }
}
