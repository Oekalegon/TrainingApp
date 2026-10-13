import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("Lab tests as a source (MVP2-158)")
struct LabTestSourceTests {
    private let day = Date(timeIntervalSince1970: 1_700_000_000)
    private var labDay: Date { day.addingTimeInterval(-40 * 86400) }

    private func settings(
        maxSource: MaxHeartRateSource = .formula, lactate: Double? = 170, lactateSource: LactateThresholdSource = .manual
    ) -> HeartRateZoneSettings {
        HeartRateZoneSettings(
            effectiveDate: day, restingHeartRateBPM: 50, maxHeartRateBPM: 190, maxHeartRateSource: maxSource,
            lactateThresholdHeartRateBPM: lactate, lactateThresholdSource: lactateSource, zoneMethod: .karvonen
        )
    }

    private func athlete(_ settings: HeartRateZoneSettings) -> AthleteProfile {
        var athlete = AthleteProfile.fixture()
        athlete.heartRateZoneHistory = [settings]
        return athlete
    }

    // MARK: Draft

    @Test("marking the max as a lab test records it with the lab test's date, not the effective date")
    func maxLabTest() {
        var draft = HeartRateSettingsDraft(prefilling: settings(), effectiveDate: day)
        #expect(!draft.maxHeartRateIsLabTest)
        #expect(!draft.hasLabTest)

        draft.maxHeartRateIsLabTest = true
        draft.labTestDate = labDay

        #expect(draft.hasLabTest)
        #expect(draft.settings().maxHeartRateSource == .labTest(measuredOn: labDay))
        #expect(draft.settings().effectiveDate == day)
    }

    @Test("a lab-tested value prefills the toggle and the date, and keeps them when saved unchanged")
    func labTestPrefills() {
        let source = settings(maxSource: .labTest(measuredOn: labDay), lactateSource: .labTest(measuredOn: labDay))
        let draft = HeartRateSettingsDraft(prefilling: source, effectiveDate: day)

        #expect(draft.maxHeartRateIsLabTest)
        #expect(draft.lactateThresholdIsLabTest)
        #expect(draft.labTestDate == labDay)
        #expect(draft.settings().maxHeartRateSource == .labTest(measuredOn: labDay))
        #expect(draft.settings().lactateThresholdSource == .labTest(measuredOn: labDay))
    }

    @Test("turning the toggle off makes the value the athlete's own")
    func untickingMakesItManual() {
        var draft = HeartRateSettingsDraft(prefilling: settings(maxSource: .labTest(measuredOn: labDay)), effectiveDate: day)

        draft.maxHeartRateIsLabTest = false

        #expect(draft.settings().maxHeartRateSource == .manual)
    }

    @Test("the lactate threshold is a lab test only while there is one")
    func lactateLabTest() {
        var draft = HeartRateSettingsDraft(prefilling: settings(lactate: nil), effectiveDate: day)
        draft.lactateThresholdIsLabTest = true
        #expect(!draft.hasLabTest)
        #expect(draft.settings().lactateThresholdSource == .manual)

        draft.lactateThresholdHeartRate = 165
        draft.labTestDate = labDay
        #expect(draft.hasLabTest)
        #expect(draft.settings().lactateThresholdSource == .labTest(measuredOn: labDay))
        #expect(draft.settings().maxHeartRateSource == .formula)
    }

    @Test("editing another value keeps a field-tested lactate threshold's source; changing it makes it manual")
    func lactateSourceFollowsEdits() {
        let id = UUID()
        var draft = HeartRateSettingsDraft(prefilling: settings(lactateSource: .fieldTest(activityID: id)), effectiveDate: day)
        draft.restingHeartRate = 48
        #expect(draft.settings().lactateThresholdSource == .fieldTest(activityID: id))

        draft.lactateThresholdHeartRate = 168
        #expect(draft.settings().lactateThresholdSource == .manual)
    }

    // MARK: Captions and estimate

    @Test("the captions name a lab test by its own date")
    func captions() {
        let viewModel = AthleteViewModel(athlete: athlete(settings(
            maxSource: .labTest(measuredOn: labDay), lactateSource: .labTest(measuredOn: labDay)
        )))
        let date = labDay.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).day().month(.abbreviated).year())

        #expect(viewModel.maxHeartRateSourceDescription == "Lab test on \(date)")
        #expect(viewModel.lactateThresholdSourceDescription == "Lab test on \(date)")
    }

    @Test("the lactate threshold caption says manual, field-tested, or nothing without one")
    func lactateCaptions() {
        #expect(AthleteViewModel(athlete: athlete(settings())).lactateThresholdSourceDescription == "Set by you")
        let measured = AthleteViewModel(athlete: athlete(settings(lactateSource: .fieldTest(activityID: UUID()))))
        #expect(measured.lactateThresholdSourceDescription?.hasPrefix("Measured in a field test on") == true)
        #expect(AthleteViewModel(athlete: athlete(settings(lactate: nil))).lactateThresholdSourceDescription == nil)
        #expect(AthleteViewModel(athlete: .fixture()).lactateThresholdSourceDescription == nil)
    }

    @Test("an age estimate is never offered over a lab-tested max, fresh or old")
    func noEstimateOverLabTest() {
        for measuredOn in [labDay, day.addingTimeInterval(-3 * 365 * 86400)] {
            var profile = athlete(settings(maxSource: .labTest(measuredOn: measuredOn)))
            profile.dateOfBirth = day.addingTimeInterval(-40 * 365.2425 * 86400)
            #expect(AthleteViewModel(athlete: profile).offeredMaxHeartRateEstimate(asOf: day) == nil)
        }
    }

    // MARK: Prompts

    private func viewModel(with settings: HeartRateZoneSettings) -> WeekViewModel {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: athlete(settings))
        return WeekViewModel(model: model, refresher: FakeRefresher(), today: day)
    }

    @Test("the raise prompt says when it would replace a lab-tested or field-tested max")
    func raisePromptNamesTheReplacedSource() {
        let suggestion = MaxHeartRateSuggestion(
            activityID: UUID(), sport: .running, activityStart: day, peakBPM: 196, currentMaxBPM: 190,
            replacesMoreReliableSource: true
        )
        let lab = viewModel(with: settings(maxSource: .labTest(measuredOn: labDay)))
        #expect(lab.maxHeartRatePromptMessage(for: suggestion).hasSuffix("This replaces a lab-tested value."))

        let field = viewModel(with: settings(maxSource: .fieldTest(activityID: UUID())))
        #expect(field.maxHeartRatePromptMessage(for: suggestion).hasSuffix("This replaces a field-tested value."))

        let plain = MaxHeartRateSuggestion(
            activityID: UUID(), sport: .running, activityStart: day, peakBPM: 196, currentMaxBPM: 190
        )
        #expect(!lab.maxHeartRatePromptMessage(for: plain).contains("This replaces"))
    }

    @Test("the field-test prompt says when it would replace a lab-tested value, for either setting")
    func fieldTestPromptNamesTheReplacedSource() {
        let model = viewModel(
            with: settings(maxSource: .labTest(measuredOn: labDay), lactateSource: .labTest(measuredOn: labDay))
        )
        let max = FieldTestResult(
            measurement: .maxHeartRate, activityID: UUID(), activityStart: day, valueBPM: 185, currentBPM: 190,
            replacesMoreReliableSource: true
        )
        let lactate = FieldTestResult(
            measurement: .lactateThresholdHeartRate, activityID: UUID(), activityStart: day, valueBPM: 160, currentBPM: 170,
            replacesMoreReliableSource: true
        )
        #expect(model.fieldTestPromptMessage(for: max).contains("This replaces a lab-tested value."))
        #expect(model.fieldTestPromptMessage(for: lactate).contains("This replaces a lab-tested value."))

        let ordinary = FieldTestResult(
            measurement: .maxHeartRate, activityID: UUID(), activityStart: day, valueBPM: 185, currentBPM: 190
        )
        #expect(!model.fieldTestPromptMessage(for: ordinary).contains("This replaces"))
    }
}
