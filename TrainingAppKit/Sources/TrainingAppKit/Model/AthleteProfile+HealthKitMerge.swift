import Foundation
import TrainingCore
import TrainingHealthKit

extension AthleteProfile {
    /// Merges a `HealthKitAthleteReader` snapshot into this profile.
    ///
    /// `sex` is replaced whenever HealthKit reports one (a biological-sex change is rare enough,
    /// and cheap enough to just overwrite, that no history is kept for it — unlike heart-rate
    /// zones below). A new `HeartRateZoneSettings` entry is appended only when both resting and
    /// estimated max heart rate are available *and* differ from ``currentHeartRateZoneSettings``,
    /// so a routine pull-to-refresh with unchanged readings doesn't pile up near-duplicate rows in
    /// `heartRateZoneHistory` — MVP 1's athlete screen only shows the current entry, but the
    /// history still feeds recomputing *past* activities' load correctly (design doc's own note on
    /// `heartRateZoneHistory` recomputation), so keeping it free of noise matters. A new entry
    /// carries over the existing entry's `lactateThresholdHeartRateBPM`/`zoneMethod`, since
    /// HealthKit never reports either — only resting/max HR and biological sex.
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
        if let resting = snapshot.restingHeartRateBPM, let max = snapshot.estimatedMaxHeartRateBPM {
            let current = merged.currentHeartRateZoneSettings
            let unchanged = current?.restingHeartRateBPM == resting && current?.maxHeartRateBPM == max
            if !unchanged {
                merged.heartRateZoneHistory.append(
                    HeartRateZoneSettings(
                        effectiveDate: today,
                        restingHeartRateBPM: resting,
                        maxHeartRateBPM: max,
                        lactateThresholdHeartRateBPM: current?.lactateThresholdHeartRateBPM,
                        zoneMethod: current?.zoneMethod ?? .karvonen
                    )
                )
            }
        }
        return merged
    }
}
