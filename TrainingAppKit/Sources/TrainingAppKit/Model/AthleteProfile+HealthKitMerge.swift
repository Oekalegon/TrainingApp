import Foundation
import TrainingCore
import TrainingHealthKit

extension AthleteProfile {
    /// Below this many bpm of difference, a new resting/max heart-rate reading is treated as
    /// "the same" rather than a real change — see ``merging(_:asOf:)``.
    ///
    /// HealthKit's `restingHeartRate` is recomputed daily from recent samples by Apple's own
    /// algorithm, so it routinely moves by a beat or two between refreshes even when the
    /// athlete's actual resting rate hasn't changed at all — comparing for exact equality would
    /// treat that as a real change on nearly every refresh. 2 bpm is a starting guess, not a
    /// researched threshold; revisit if it turns out too loose or too tight in practice.
    static let heartRateChangeToleranceBPM: Double = 2

    /// Merges a `HealthKitAthleteReader` snapshot into this profile.
    ///
    /// `sex` is replaced whenever HealthKit reports one (a biological-sex change is rare enough,
    /// and cheap enough to just overwrite, that no history is kept for it — unlike heart-rate
    /// zones below). A new `HeartRateZoneSettings` entry is appended only when both resting and
    /// estimated max heart rate are available *and* differ from ``currentHeartRateZoneSettings``
    /// by more than ``heartRateChangeToleranceBPM``, so a routine pull-to-refresh with
    /// essentially-unchanged readings doesn't pile up near-duplicate rows in
    /// `heartRateZoneHistory` — MVP 1's athlete screen only shows the current entry, but the
    /// history still feeds recomputing *past* activities' load correctly (design doc's own note on
    /// `heartRateZoneHistory` recomputation), so keeping it free of noise matters. A new entry
    /// carries over the existing entry's `lactateThresholdHeartRateBPM`/`zoneMethod`, since
    /// HealthKit never reports either — only resting/max HR and biological sex.
    ///
    /// A max heart rate measured in a workout (`maxHeartRateSource` `.workout`, MVP2-56) is never
    /// replaced by a lower formula estimate: the measured value is a lower bound on the true max,
    /// while the estimate is only a guess from age. See ``mergedMaxHeartRate(estimate:current:)``.
    ///
    /// - Parameters:
    ///   - snapshot: What `HealthKitAthleteReader.snapshot(asOf:)` could read; any field may be
    ///     `nil` (denied authorization or never recorded).
    ///   - today: The date to stamp a new `HeartRateZoneSettings` entry's `effectiveDate` with.
    func merging(_ snapshot: HealthKitAthleteSnapshot, asOf today: Date) -> AthleteProfile {
        var merged = self
        if let sex = snapshot.biologicalSex {
            merged.sex = sex
        }
        if let resting = snapshot.restingHeartRateBPM, let estimate = snapshot.estimatedMaxHeartRateBPM {
            let current = merged.currentHeartRateZoneSettings
            let max = Self.mergedMaxHeartRate(estimate: estimate, current: current)
            let tolerance = Self.heartRateChangeToleranceBPM
            let restingUnchanged = current.map { abs($0.restingHeartRateBPM - resting) < tolerance } ?? false
            let maxUnchanged = current.map { abs($0.maxHeartRateBPM - max.bpm) < tolerance } ?? false
            if !(restingUnchanged && maxUnchanged) {
                merged.heartRateZoneHistory.append(
                    HeartRateZoneSettings(
                        effectiveDate: today,
                        restingHeartRateBPM: resting,
                        maxHeartRateBPM: max.bpm,
                        maxHeartRateSource: max.source,
                        lactateThresholdHeartRateBPM: current?.lactateThresholdHeartRateBPM,
                        zoneMethod: current?.zoneMethod ?? .karvonen
                    )
                )
            }
        }
        return merged
    }

    /// The max heart rate a merged entry should carry: HealthKit's formula `estimate`, unless
    /// `current` holds a measured max at least as high, which is kept with its source.
    ///
    /// - Parameters:
    ///   - estimate: The age-formula estimate from HealthKit's date of birth, in bpm.
    ///   - current: The settings currently in effect, if any.
    /// - Returns: The max heart rate to record and where it came from.
    static func mergedMaxHeartRate(
        estimate: Double, current: HeartRateZoneSettings?
    ) -> (bpm: Double, source: MaxHeartRateSource) {
        if let current, current.maxHeartRateSource != .formula, current.maxHeartRateBPM >= estimate {
            return (current.maxHeartRateBPM, current.maxHeartRateSource)
        }
        return (estimate, .formula)
    }
}
