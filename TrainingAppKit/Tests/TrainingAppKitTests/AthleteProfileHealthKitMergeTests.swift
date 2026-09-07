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

    @Test("only a partial HR reading (resting without max) doesn't append an entry")
    func partialHeartRateDataDoesNotAppend() {
        let athlete = AthleteProfile.fixture()
        let snapshot = HealthKitAthleteSnapshot(restingHeartRateBPM: 48, biologicalSex: nil, estimatedMaxHeartRateBPM: nil)

        let merged = athlete.merging(snapshot, asOf: day(0))

        #expect(merged.heartRateZoneHistory.isEmpty)
    }
}
