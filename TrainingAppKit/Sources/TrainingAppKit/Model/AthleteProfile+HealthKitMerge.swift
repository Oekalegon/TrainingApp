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
    /// `sex` and `dateOfBirth` are replaced whenever HealthKit reports one (a biological-sex change is
    /// rare enough, and cheap enough to just overwrite, that no history is kept for it — unlike
    /// heart-rate zones below).
    ///
    /// The resting heart rate follows HealthKit only while ``usesHealthKitRestingHeartRate`` is on
    /// (MVP2-132); with it off the athlete's own entries stand and HealthKit's reading is ignored. When
    /// it's on, a new `HeartRateZoneSettings` entry is appended only when the reading differs from
    /// ``currentHeartRateZoneSettings`` by at least ``heartRateChangeToleranceBPM``, so a routine
    /// pull-to-refresh with essentially-unchanged readings doesn't pile up near-duplicate rows in
    /// `heartRateZoneHistory` — the history feeds recomputing *past* activities' load correctly (design
    /// doc's own note on `heartRateZoneHistory` recomputation), so keeping it free of noise matters.
    ///
    /// The maximum heart rate is never changed here. A new entry carries over the current entry's max
    /// (with its source), lactate threshold and zone method, since HealthKit reports none of them; and
    /// the age estimate only seeds the very first entry. Later estimates, which drift as the athlete
    /// ages, are offered for the athlete to accept (``AthleteViewModel/offeredMaxHeartRateEstimate(asOf:)``)
    /// rather than applied.
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
        // The date of birth is a fact, not a reading: replace it whenever HealthKit has one (MVP2-124).
        if let dateOfBirth = snapshot.dateOfBirth {
            merged.dateOfBirth = dateOfBirth
        }
        guard usesHealthKitRestingHeartRate, let resting = snapshot.restingHeartRateBPM else { return merged }
        if let current = merged.currentHeartRateZoneSettings {
            if abs(current.restingHeartRateBPM - resting) >= Self.heartRateChangeToleranceBPM {
                var entry = current
                entry.effectiveDate = today
                entry.restingHeartRateBPM = resting
                merged.heartRateZoneHistory.append(entry)
            }
        } else if let estimate = snapshot.estimatedMaxHeartRateBPM {
            merged.heartRateZoneHistory.append(
                HeartRateZoneSettings(
                    effectiveDate: today,
                    restingHeartRateBPM: resting,
                    maxHeartRateBPM: estimate,
                    maxHeartRateSource: .formula,
                    zoneMethod: .karvonen
                )
            )
        }
        return merged
    }
}
