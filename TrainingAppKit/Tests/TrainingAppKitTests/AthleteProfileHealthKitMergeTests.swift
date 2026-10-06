import Foundation
import Testing
import TrainingCore
import TrainingHealthKit
@testable import TrainingAppKit

@Suite("AthleteProfile.merging(_:asOf:)")
struct AthleteProfileHealthKitMergeTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func emptySnapshot() -> HealthKitAthleteSnapshot {
        HealthKitAthleteSnapshot(restingHeartRateBPM: nil, biologicalSex: nil, estimatedMaxHeartRateBPM: nil)
    }

    @Test("an all-nil snapshot leaves the profile unchanged")
    func emptySnapshotLeavesProfileUnchanged() {
        let athlete = AthleteProfile.fixture()

        let merged = athlete.merging(emptySnapshot(), asOf: day(0))

        #expect(merged == athlete)
    }

    @Test("biological sex is overwritten whenever HealthKit reports one")
    func sexIsOverwrittenWhenReported() {
        let athlete = AthleteProfile.fixture()
        let snapshot = HealthKitAthleteSnapshot(restingHeartRateBPM: nil, biologicalSex: .female, estimatedMaxHeartRateBPM: nil)

        let merged = athlete.merging(snapshot, asOf: day(0))

        #expect(merged.sex == .female)
    }

    @Test("the date of birth is stored whenever HealthKit reports one, and kept when it doesn't (MVP2-124)")
    func dateOfBirthIsStoredWhenReported() {
        let athlete = AthleteProfile.fixture()
        let born = day(-10_000)
        let snapshot = HealthKitAthleteSnapshot(
            restingHeartRateBPM: nil, biologicalSex: nil, estimatedMaxHeartRateBPM: nil, dateOfBirth: born
        )

        let merged = athlete.merging(snapshot, asOf: day(0))
        #expect(merged.dateOfBirth == born)

        // A later read that couldn't get it (denied, offline) doesn't wipe what was stored.
        #expect(merged.merging(emptySnapshot(), asOf: day(1)).dateOfBirth == born)
    }

    @Test("a new heart-rate zone entry is appended when both resting and max HR are present and no entry exists yet")
    func appendsFirstZoneEntry() {
        let athlete = AthleteProfile.fixture()
        let snapshot = HealthKitAthleteSnapshot(restingHeartRateBPM: 48, biologicalSex: nil, estimatedMaxHeartRateBPM: 190)

        let merged = athlete.merging(snapshot, asOf: day(0))

        #expect(merged.heartRateZoneHistory.count == 1)
        #expect(merged.currentHeartRateZoneSettings?.restingHeartRateBPM == 48)
        #expect(merged.currentHeartRateZoneSettings?.maxHeartRateBPM == 190)
        #expect(merged.currentHeartRateZoneSettings?.zoneMethod == .karvonen)
        #expect(merged.currentHeartRateZoneSettings?.effectiveDate == day(0))
    }

    @Test("no new entry is appended when resting/max HR match the current entry")
    func doesNotAppendWhenUnchanged() {
        let existing = HeartRateZoneSettings(effectiveDate: day(0), restingHeartRateBPM: 48, maxHeartRateBPM: 190)
        var athlete = AthleteProfile.fixture()
        athlete.heartRateZoneHistory = [existing]
        let snapshot = HealthKitAthleteSnapshot(restingHeartRateBPM: 48, biologicalSex: nil, estimatedMaxHeartRateBPM: 190)

        let merged = athlete.merging(snapshot, asOf: day(5))

        #expect(merged.heartRateZoneHistory.count == 1)
        #expect(merged == athlete)
    }

    @Test("a new entry is appended when resting or max HR actually changed")
    func appendsNewEntryWhenChanged() {
        let existing = HeartRateZoneSettings(effectiveDate: day(0), restingHeartRateBPM: 48, maxHeartRateBPM: 190)
        var athlete = AthleteProfile.fixture()
        athlete.heartRateZoneHistory = [existing]
        let snapshot = HealthKitAthleteSnapshot(restingHeartRateBPM: 45, biologicalSex: nil, estimatedMaxHeartRateBPM: 190)

        let merged = athlete.merging(snapshot, asOf: day(5))

        #expect(merged.heartRateZoneHistory.count == 2)
        #expect(merged.currentHeartRateZoneSettings?.restingHeartRateBPM == 45)
    }

    @Test("a new entry carries over the existing entry's lactate threshold and zone method")
    func newEntryPreservesLactateThresholdAndMethod() {
        let existing = HeartRateZoneSettings(
            effectiveDate: day(0), restingHeartRateBPM: 48, maxHeartRateBPM: 190,
            lactateThresholdHeartRateBPM: 165, zoneMethod: .lactateThreshold
        )
        var athlete = AthleteProfile.fixture()
        athlete.heartRateZoneHistory = [existing]
        let snapshot = HealthKitAthleteSnapshot(restingHeartRateBPM: 45, biologicalSex: nil, estimatedMaxHeartRateBPM: 188)

        let merged = athlete.merging(snapshot, asOf: day(5))

        #expect(merged.currentHeartRateZoneSettings?.lactateThresholdHeartRateBPM == 165)
        #expect(merged.currentHeartRateZoneSettings?.zoneMethod == .lactateThreshold)
    }

    @Test("a small, sub-tolerance fluctuation in resting HR doesn't append a new entry")
    func smallRestingHeartRateFluctuationDoesNotAppend() {
        // HealthKit's resting HR is recomputed daily and routinely moves by a beat or two even
        // when the athlete's actual resting rate hasn't changed — this shouldn't read as a change.
        let existing = HeartRateZoneSettings(effectiveDate: day(0), restingHeartRateBPM: 48, maxHeartRateBPM: 190)
        var athlete = AthleteProfile.fixture()
        athlete.heartRateZoneHistory = [existing]
        let snapshot = HealthKitAthleteSnapshot(restingHeartRateBPM: 47, biologicalSex: nil, estimatedMaxHeartRateBPM: 190)

        let merged = athlete.merging(snapshot, asOf: day(5))

        #expect(merged.heartRateZoneHistory.count == 1)
        #expect(merged == athlete)
    }

    @Test("only a partial HR reading (resting without max) doesn't append an entry")
    func partialHeartRateDataDoesNotAppend() {
        let athlete = AthleteProfile.fixture()
        let snapshot = HealthKitAthleteSnapshot(restingHeartRateBPM: 48, biologicalSex: nil, estimatedMaxHeartRateBPM: nil)

        let merged = athlete.merging(snapshot, asOf: day(0))

        #expect(merged.heartRateZoneHistory.isEmpty)
    }

    @Test("a max measured in a workout isn't replaced by a lower formula estimate on the next refresh (MVP2-56)")
    func measuredMaxSurvivesLowerEstimate() {
        let activityID = UUID()
        var athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 178)
        athlete = athlete.raisingMaxHeartRate(to: 189, from: day(0), source: .workout(activityID: activityID))
        let snapshot = HealthKitAthleteSnapshot(restingHeartRateBPM: 50, biologicalSex: nil, estimatedMaxHeartRateBPM: 178)

        let merged = athlete.merging(snapshot, asOf: day(5))

        #expect(merged == athlete)
        #expect(merged.currentHeartRateZoneSettings?.maxHeartRateBPM == 189)
    }

    @Test("a resting-HR change keeps the measured max and its source in the new entry (MVP2-56)")
    func restingChangeCarriesMeasuredMax() {
        let activityID = UUID()
        var athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 178)
        athlete = athlete.raisingMaxHeartRate(to: 189, from: day(0), source: .workout(activityID: activityID))
        let snapshot = HealthKitAthleteSnapshot(restingHeartRateBPM: 45, biologicalSex: nil, estimatedMaxHeartRateBPM: 178)

        let merged = athlete.merging(snapshot, asOf: day(5))

        let current = merged.currentHeartRateZoneSettings
        #expect(current?.effectiveDate == day(5))
        #expect(current?.restingHeartRateBPM == 45)
        #expect(current?.maxHeartRateBPM == 189)
        #expect(current?.maxHeartRateSource == .workout(activityID: activityID))
    }

    @Test("a changed age estimate never replaces the max on its own: the athlete is asked instead (MVP2-132)")
    func higherEstimateDoesNotReplaceMax() {
        var athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 170)
        athlete = athlete.raisingMaxHeartRate(to: 175, from: day(0), source: .workout(activityID: UUID()))
        let snapshot = HealthKitAthleteSnapshot(restingHeartRateBPM: 50, biologicalSex: nil, estimatedMaxHeartRateBPM: 182)

        #expect(athlete.merging(snapshot, asOf: day(5)) == athlete)
    }

    @Test("a changed estimate alone, with the resting HR unchanged, appends nothing (MVP2-132)")
    func changedEstimateAloneAppendsNothing() {
        let athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        let snapshot = HealthKitAthleteSnapshot(restingHeartRateBPM: 50, biologicalSex: nil, estimatedMaxHeartRateBPM: 180)

        #expect(athlete.merging(snapshot, asOf: day(5)) == athlete)
    }

    @Test("with the HealthKit resting-HR switch off, HealthKit's reading is ignored (MVP2-132)")
    func switchOffIgnoresHealthKitRestingHeartRate() {
        var athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        athlete.usesHealthKitRestingHeartRate = false
        let snapshot = HealthKitAthleteSnapshot(restingHeartRateBPM: 40, biologicalSex: .female, estimatedMaxHeartRateBPM: 190, dateOfBirth: day(-9000))

        let merged = athlete.merging(snapshot, asOf: day(5))

        #expect(merged.heartRateZoneHistory == athlete.heartRateZoneHistory)
        // The rest of the snapshot still applies.
        #expect(merged.sex == .female)
        #expect(merged.dateOfBirth == day(-9000))
    }

    @Test("with the switch off and no entry yet, nothing is created: the athlete enters their own (MVP2-132)")
    func switchOffCreatesNoFirstEntry() {
        var athlete = AthleteProfile.fixture()
        athlete.heartRateZoneHistory = []
        athlete.usesHealthKitRestingHeartRate = false
        let snapshot = HealthKitAthleteSnapshot(restingHeartRateBPM: 48, biologicalSex: nil, estimatedMaxHeartRateBPM: 190)

        #expect(athlete.merging(snapshot, asOf: day(0)).heartRateZoneHistory.isEmpty)
    }

    @Test("a resting-HR change keeps a manually entered max and its source (MVP2-132)")
    func restingChangeCarriesManualMax() {
        var athlete = AthleteProfile.fixture()
        athlete = athlete.recordingHeartRateSettings(
            HeartRateZoneSettings(effectiveDate: day(0), restingHeartRateBPM: 50, maxHeartRateBPM: 186, maxHeartRateSource: .manual)
        )
        let snapshot = HealthKitAthleteSnapshot(restingHeartRateBPM: 44, biologicalSex: nil, estimatedMaxHeartRateBPM: 180)

        let current = athlete.merging(snapshot, asOf: day(5)).currentHeartRateZoneSettings

        #expect(current?.restingHeartRateBPM == 44)
        #expect(current?.maxHeartRateBPM == 186)
        #expect(current?.maxHeartRateSource == .manual)
    }
}
