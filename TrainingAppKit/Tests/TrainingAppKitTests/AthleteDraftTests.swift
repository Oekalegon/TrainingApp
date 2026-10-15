import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@Suite("Athlete edit drafts (MVP2-132)")
struct AthleteDraftTests {
    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    private func settings(max: Double = 190, source: MaxHeartRateSource = .formula) -> HeartRateZoneSettings {
        HeartRateZoneSettings(
            effectiveDate: day, restingHeartRateBPM: 50, maxHeartRateBPM: max, maxHeartRateSource: source,
            lactateThresholdHeartRateBPM: 170, zoneMethod: .lactateThreshold
        )
    }

    // MARK: Heart-rate settings

    @Test("a draft prefilled from settings reproduces them, with the chosen date")
    func prefillsFromSettings() {
        let later = day.addingTimeInterval(86400 * 3)
        let draft = HeartRateSettingsDraft(prefilling: settings(), effectiveDate: later)

        let result = draft.settings()

        #expect(result.effectiveDate == later)
        #expect(result.restingHeartRateBPM == 50)
        #expect(result.maxHeartRateBPM == 190)
        #expect(result.lactateThresholdHeartRateBPM == 170)
        #expect(result.zoneMethod == .lactateThreshold)
        #expect(draft.validationMessage == nil)
    }

    @Test("leaving the max alone keeps its source; changing it makes it the athlete's own")
    func maxSourceFollowsEdits() {
        let activityID = UUID()
        var draft = HeartRateSettingsDraft(prefilling: settings(source: .workout(activityID: activityID)), effectiveDate: day)
        #expect(draft.settings().maxHeartRateSource == .workout(activityID: activityID))

        draft.restingHeartRate = 48
        #expect(draft.settings().maxHeartRateSource == .workout(activityID: activityID))

        draft.maxHeartRate = 192
        #expect(draft.settings().maxHeartRateSource == .manual)

        // Back to the original value: it's the original again.
        draft.maxHeartRate = 190
        #expect(draft.settings().maxHeartRateSource == .workout(activityID: activityID))
    }

    @Test("a draft with no settings to start from uses typical values and the athlete's own source")
    func typicalDefaults() {
        let draft = HeartRateSettingsDraft(prefilling: nil, effectiveDate: day)

        #expect(draft.validationMessage == nil)
        #expect(draft.settings().maxHeartRateSource == .manual)
        #expect(draft.settings().lactateThresholdHeartRateBPM == nil)
    }

    @Test("values out of range, a max too near the resting rate and a bad lactate threshold are refused")
    func validation() {
        var draft = HeartRateSettingsDraft(prefilling: settings(), effectiveDate: day)

        draft.restingHeartRate = 10
        #expect(draft.validationMessage != nil)
        draft.restingHeartRate = 50

        draft.maxHeartRate = 240
        #expect(draft.validationMessage != nil)
        draft.maxHeartRate = 60
        #expect(draft.validationMessage != nil)
        draft.maxHeartRate = 190

        draft.lactateThresholdHeartRate = 195
        #expect(draft.validationMessage != nil)
        draft.lactateThresholdHeartRate = 40
        #expect(draft.validationMessage != nil)
        draft.lactateThresholdHeartRate = 170
        #expect(draft.validationMessage == nil)
    }

    @Test("the lactate-threshold method needs a lactate threshold")
    func lactateMethodNeedsAThreshold() {
        var draft = HeartRateSettingsDraft(prefilling: settings(), effectiveDate: day)
        draft.lactateThresholdHeartRate = nil
        #expect(draft.validationMessage != nil)

        draft.zoneMethod = .karvonen
        #expect(draft.validationMessage == nil)
    }

    // MARK: Pace

    @Test("a pace draft splits the threshold pace into minutes and seconds and joins them again")
    func paceDraftRoundTrips() {
        let draft = PaceDraft(prefilling: PaceModel(thresholdPaceSecondsPerKilometer: 275), effectiveDate: day)

        #expect(draft.minutes == 4)
        #expect(draft.seconds == 35)
        #expect(draft.thresholdPaceSecondsPerKilometer == 275)
        #expect(draft.validationMessage == nil)
    }

    @Test("a pace draft with nothing to start from begins at 5:00 per kilometer")
    func paceDraftDefault() {
        #expect(PaceDraft(prefilling: nil, effectiveDate: day).thresholdPaceSecondsPerKilometer == 300)
    }

    @Test("paces outside 2:00 to 20:00 per kilometer, and seconds above 59, are refused")
    func paceValidation() {
        var draft = PaceDraft(prefilling: nil, effectiveDate: day)
        draft.minutes = 1
        draft.seconds = 30
        #expect(draft.validationMessage != nil)
        draft.minutes = 25
        draft.seconds = 0
        #expect(draft.validationMessage != nil)
        draft.minutes = 4
        draft.seconds = 75
        #expect(draft.validationMessage != nil)
        draft.seconds = 0
        #expect(draft.validationMessage == nil)
    }

    @Test("the recorded pace model keeps the zone multipliers of the one it's based on")
    func paceModelKeepsMultipliers() {
        let base = PaceModel(thresholdPaceSecondsPerKilometer: 300, zonePaceMultipliers: [1: 1.5, 4: 1.0])
        var draft = PaceDraft(prefilling: base, effectiveDate: day)
        draft.minutes = 4

        let model = draft.paceModel(basedOn: base)

        #expect(model.thresholdPaceSecondsPerKilometer == 240 + Double(draft.seconds))
        #expect(model.zonePaceMultipliers == base.zonePaceMultipliers)
    }
}
