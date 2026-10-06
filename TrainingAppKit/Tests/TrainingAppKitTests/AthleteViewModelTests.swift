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

    @Test("ageText is the athlete's age in whole years, and nil until a date of birth is on record (MVP2-124)")
    func ageText() {
        var athlete = AthleteProfile.fixture()
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(AthleteViewModel(athlete: athlete).ageText(asOf: today) == nil)

        athlete.dateOfBirth = today.addingTimeInterval(-40.5 * 365.2425 * 86400)
        #expect(AthleteViewModel(athlete: athlete).ageText(asOf: today) == "40")
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

@Suite("AthleteViewModel editing support (MVP2-132)")
struct AthleteViewModelEditingTests {
    private let today = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("a manually entered max says when it was set")
    func manualMaxDescription() {
        var athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        athlete = athlete.recordingHeartRateSettings(
            HeartRateZoneSettings(effectiveDate: today, restingHeartRateBPM: 50, maxHeartRateBPM: 186, maxHeartRateSource: .manual)
        )

        #expect(AthleteViewModel(athlete: athlete).maxHeartRateSourceDescription?.hasPrefix("Set by you on") == true)
    }

    @Test("both histories list newest first")
    func historiesNewestFirst() {
        var athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        athlete = athlete
            .recordingHeartRateSettings(HeartRateZoneSettings(effectiveDate: today, restingHeartRateBPM: 48, maxHeartRateBPM: 186))
            .recordingPaceModel(PaceModel(thresholdPaceSecondsPerKilometer: 260), from: today)
        let viewModel = AthleteViewModel(athlete: athlete)

        #expect(viewModel.heartRateHistory.map(\.restingHeartRateBPM) == [48, 50])
        #expect(viewModel.paceHistory.map(\.paceModel.thresholdPaceSecondsPerKilometer) == [260, 300])
    }

    @Test("an entry effective since the beginning of time is edited as a new one from today")
    func editingDateForTheFirstEntry() {
        #expect(AthleteViewModel.editingDate(for: .distantPast, asOf: today) == today)
        #expect(AthleteViewModel.editingDate(for: today.addingTimeInterval(-86400), asOf: today) == today.addingTimeInterval(-86400))
    }

    @Test("the age estimate is offered only while the max is itself an estimate, and only when it differs enough")
    func offeredEstimate() {
        var athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        athlete.dateOfBirth = today.addingTimeInterval(-40 * 365.2425 * 86400)
        // 208 - 0.7 * 40 = 180: ten above the stored 190 estimate.
        #expect(AthleteViewModel(athlete: athlete).offeredMaxHeartRateEstimate(asOf: today) == 180)

        // Within tolerance: nothing to offer.
        let close = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 179)
        var closeWithBirth = close
        closeWithBirth.dateOfBirth = athlete.dateOfBirth
        #expect(AthleteViewModel(athlete: closeWithBirth).offeredMaxHeartRateEstimate(asOf: today) == nil)

        // The athlete's own max isn't compared with a formula.
        let manual = athlete.recordingHeartRateSettings(
            HeartRateZoneSettings(effectiveDate: today, restingHeartRateBPM: 50, maxHeartRateBPM: 200, maxHeartRateSource: .manual)
        )
        #expect(AthleteViewModel(athlete: manual).offeredMaxHeartRateEstimate(asOf: today) == nil)

        // No date of birth, no estimate.
        #expect(AthleteViewModel(athlete: AthleteProfile.fixture()).offeredMaxHeartRateEstimate(asOf: today) == nil)
    }

    @Test("choosing a zone method drafts the current settings from today with only the method changed")
    func zoneMethodDraft() {
        let athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        let viewModel = AthleteViewModel(athlete: athlete)

        let draft = viewModel.zoneMethodDraft(.percentageOfMaxHeartRate, asOf: today)

        let settings = draft?.settings()
        #expect(settings?.zoneMethod == .percentageOfMaxHeartRate)
        #expect(settings?.effectiveDate == today)
        #expect(settings?.restingHeartRateBPM == 50)
        #expect(settings?.maxHeartRateBPM == 190)
        #expect(draft?.needsLactateThresholdReview == false)
        #expect(draft?.validationMessage == nil)
    }

    @Test("choosing the lactate-threshold method without a threshold asks for one instead of inventing it")
    func zoneMethodNeedingAThreshold() {
        let viewModel = AthleteViewModel(athlete: AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190))

        let draft = viewModel.zoneMethodDraft(.lactateThreshold, asOf: today)

        #expect(draft?.needsLactateThresholdReview == true)
        #expect(draft?.lactateThresholdHeartRate != nil)

        // With a threshold on record it can be applied as it is.
        var athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        athlete.heartRateZoneHistory[0].lactateThresholdHeartRateBPM = 168
        let ready = AthleteViewModel(athlete: athlete).zoneMethodDraft(.lactateThreshold, asOf: today)
        #expect(ready?.needsLactateThresholdReview == false)
        #expect(ready?.settings().lactateThresholdHeartRateBPM == 168)
    }

    @Test("with no settings on record there's no draft for a zone method")
    func noZoneMethodDraftWithoutSettings() {
        #expect(AthleteViewModel(athlete: AthleteProfile.fixture()).zoneMethodDraft(.karvonen, asOf: today) == nil)
    }

    @Test("the avatar picture comes from the profile")
    func avatarImageData() {
        var athlete = AthleteProfile.fixture()
        #expect(AthleteViewModel(athlete: athlete).avatarImageData == nil)

        athlete.avatarImageData = Data([1, 2, 3])
        #expect(AthleteViewModel(athlete: athlete).avatarImageData == Data([1, 2, 3]))
    }
}
