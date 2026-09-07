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
}
