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
        draft.maxLabTestDate = labDay

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
        #expect(draft.maxLabTestDate == labDay)
        #expect(draft.lactateLabTestDate == labDay)
        #expect(draft.settings().maxHeartRateSource == .labTest(measuredOn: labDay))
        #expect(draft.settings().lactateThresholdSource == .labTest(measuredOn: labDay))
    }

    @Test("each value keeps its own lab test date, so saving unchanged doesn't move the other's")
    func datesStayApart() {
        let thresholdDay = labDay.addingTimeInterval(-20 * 86400)
        let source = settings(maxSource: .labTest(measuredOn: labDay), lactateSource: .labTest(measuredOn: thresholdDay))
        var draft = HeartRateSettingsDraft(prefilling: source, effectiveDate: day)

        draft.zoneMethod = .percentageOfMaxHeartRate

        #expect(draft.settings().maxHeartRateSource == .labTest(measuredOn: labDay))
        #expect(draft.settings().lactateThresholdSource == .labTest(measuredOn: thresholdDay))
    }

    @Test("a lab test can't be in the future or after the day the settings take effect")
    func labDateValidation() {
        var draft = HeartRateSettingsDraft(prefilling: settings(), effectiveDate: day)
        draft.maxHeartRateIsLabTest = true
        #expect(draft.validationMessage(asOf: day) == nil)

        draft.maxLabTestDate = day.addingTimeInterval(3 * 86400)
        #expect(draft.validationMessage(asOf: day) == "A lab test can't be in the future.")
        // Not future, but later than the day the settings start.
        #expect(draft.validationMessage(asOf: day.addingTimeInterval(10 * 86400))
            == "A lab test can't be after the day the settings take effect.")

        // A date that's only checked while its switch is on.
        draft.maxHeartRateIsLabTest = false
        #expect(draft.validationMessage(asOf: day) == nil)
    }

    @Test("a new lab test's date starts at the effective date, but never in the future")
    func labDateDefault() {
        let future = day.addingTimeInterval(5 * 86400)
        let draft = HeartRateSettingsDraft(prefilling: settings(), effectiveDate: future, asOf: day)
        #expect(draft.maxLabTestDate == day)
        #expect(draft.lactateLabTestDate == day)

        let past = HeartRateSettingsDraft(prefilling: settings(), effectiveDate: labDay, asOf: day)
        #expect(past.maxLabTestDate == labDay)
    }

    @Test("the footer's freshness windows come from TrainingKit")
    func freshnessText() {
        let text = HeartRateSettingsDraft.labTestFreshnessText
        #expect(text.max == "2 years")
        #expect(text.lactateThreshold == "90 days")
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
        draft.lactateLabTestDate = labDay
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

    @Test("no note is added when the value in effect isn't a lab or field test")
    func noNoteForOtherSources() {
        for source: MaxHeartRateSource in [.formula, .manual, .workout(activityID: UUID())] {
            #expect(viewModel(with: settings(maxSource: source)).replacedMaxSourceNote(at: day).isEmpty)
        }
        #expect(viewModel(with: settings(lactateSource: .manual)).replacedLactateSourceNote(at: day).isEmpty)
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
