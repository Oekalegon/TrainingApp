import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@Suite("AthleteViewModel")
struct AthleteViewModelTests {
    @Test("displayName falls back to a generic label when the athlete has no name yet")
    func displayNameFallsBackWhenEmpty() {
        let athlete = AthleteProfile.fixture()
        let viewModel = AthleteViewModel(athlete: athlete)

        #expect(viewModel.displayName == "Athlete")
    }

    @Test("displayName uses the athlete's name when set")
    func displayNameUsesAthleteName() {
        let athlete = AthleteProfile(
            name: "Dieudonné Willems",
            sex: .unspecified,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
            timeZone: TimeZone(identifier: "UTC")!,
            heartRateZoneHistory: []
        )
        let viewModel = AthleteViewModel(athlete: athlete)

        #expect(viewModel.displayName == "Dieudonné Willems")
    }

    @Test("initials takes the first letter of up to the first two words")
    func initialsTakesFirstTwoWords() {
        let athlete = AthleteProfile(
            name: "Ada Lovelace",
            sex: .unspecified,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
            timeZone: TimeZone(identifier: "UTC")!,
            heartRateZoneHistory: []
        )
        let viewModel = AthleteViewModel(athlete: athlete)

        #expect(viewModel.initials == "AL")
    }

    @Test("initials derives from the displayName fallback when there's no name")
    func initialsDerivesFromDisplayNameFallbackWhenNoName() {
        let athlete = AthleteProfile.fixture()
        let viewModel = AthleteViewModel(athlete: athlete)

        #expect(viewModel.displayName == "Athlete")
        #expect(viewModel.initials == "A")
    }

    @Test("currentHeartRateZoneSettings reflects the athlete's most recent entry")
    func currentHeartRateZoneSettingsReflectsAthlete() {
        let settings = HeartRateZoneSettings(
            effectiveDate: .distantPast, restingHeartRateBPM: 48, maxHeartRateBPM: 188
        )
        let athlete = AthleteProfile(
            sex: .male,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
            timeZone: TimeZone(identifier: "UTC")!,
            heartRateZoneHistory: [settings]
        )
        let viewModel = AthleteViewModel(athlete: athlete)

        #expect(viewModel.currentHeartRateZoneSettings == settings)
    }

    @Test("heartRateZoneRanges lists all five zones in order, with bpm ranges derived from the current settings")
    func heartRateZoneRangesListsAllFiveZonesInOrder() throws {
        let settings = HeartRateZoneSettings(
            effectiveDate: .distantPast, restingHeartRateBPM: 50, maxHeartRateBPM: 190
        )
        let athlete = AthleteProfile(
            sex: .male,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
            timeZone: TimeZone(identifier: "UTC")!,
            heartRateZoneHistory: [settings]
        )
        let viewModel = AthleteViewModel(athlete: athlete)

        let ranges = viewModel.heartRateZoneRanges
        #expect(ranges.map(\.zone) == HeartRateZone.allCases)
        // Zone 1 is 50%-60% HRR: resting + ratio * (max - resting), i.e. 120...134 bpm here --
        // same fixture and expected numbers as TrainingKit's own zoneBPMRange test.
        let zone1 = try #require(ranges.first { $0.zone == .recovery })
        #expect(zone1.bpmRange == 120...134)
    }

    @Test("heartRateZoneRanges is empty when the athlete has no zone settings on record")
    func heartRateZoneRangesEmptyWithoutSettings() {
        let athlete = AthleteProfile.fixture()
        let viewModel = AthleteViewModel(athlete: athlete)

        #expect(viewModel.heartRateZoneRanges.isEmpty)
    }

    @Test("heartRateZoneRanges is empty for the lactate-threshold method with no LTHR set")
    func heartRateZoneRangesEmptyWithoutLTHR() {
        let settings = HeartRateZoneSettings(
            effectiveDate: .distantPast, restingHeartRateBPM: 50, maxHeartRateBPM: 190,
            zoneMethod: .lactateThreshold
        )
        let athlete = AthleteProfile(
            sex: .male,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 240),
            timeZone: TimeZone(identifier: "UTC")!,
            heartRateZoneHistory: [settings]
        )
        let viewModel = AthleteViewModel(athlete: athlete)

        #expect(viewModel.heartRateZoneRanges.isEmpty)
    }

    @Test("thresholdPaceText formats seconds per kilometer as minutes:seconds /km")
    func thresholdPaceTextFormatsCorrectly() {
        let athlete = AthleteProfile(
            sex: .unspecified,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 245),
            timeZone: TimeZone(identifier: "UTC")!,
            heartRateZoneHistory: []
        )
        let viewModel = AthleteViewModel(athlete: athlete)

        #expect(viewModel.thresholdPaceText == "4:05 /km")
    }

    @Test("maxHeartRateSourceDescription is nil without heart-rate settings")
    func maxHeartRateSourceNilWithoutSettings() {
        #expect(AthleteViewModel(athlete: .fixture()).maxHeartRateSourceDescription == nil)
    }

    @Test("a formula-based max HR is described as estimated from age")
    func formulaMaxDescribedAsEstimate() {
        let viewModel = AthleteViewModel(athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 178))

        #expect(viewModel.maxHeartRateSourceDescription == "Estimated from age")
    }

    @Test("a workout-measured max HR names the workout's date, even after later entries carry it forward")
    func workoutMaxNamesWorkoutDate() {
        let workoutDay = Date(timeIntervalSince1970: 1_700_000_000)
        var athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 178)
        athlete.heartRateZoneHistory.append(HeartRateZoneSettings(
            effectiveDate: workoutDay.addingTimeInterval(20 * 86400), restingHeartRateBPM: 47, maxHeartRateBPM: 178
        ))
        athlete = athlete.raisingMaxHeartRate(to: 189, from: workoutDay, source: .workout(activityID: UUID()))

        let viewModel = AthleteViewModel(athlete: athlete)

        let date = workoutDay.formatted(
            Date.FormatStyle(timeZone: athlete.timeZone).day().month(.abbreviated).year()
        )
        #expect(viewModel.maxHeartRateSourceDescription == "Measured in a workout on \(date)")
    }
}
