import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// MVP5-112: the peak weekly volume field.
@Suite("PeakVolumeDraft")
struct PeakVolumeDraftTests {
    @Test("empty is valid and has no value")
    func empty() {
        let draft = PeakVolumeDraft(measure: .trimp, text: "  ")
        #expect(draft.validation == .empty)
        #expect(draft.value == nil)
        #expect(draft.message == nil)
    }

    @Test("distance converts to meters in either system, accepting a decimal comma")
    func distance() {
        #expect(PeakVolumeDraft(measure: .distance, text: "60", distanceSystem: .metric).value == 60_000)
        #expect(PeakVolumeDraft(measure: .distance, text: "37,5", distanceSystem: .metric).value == 37_500)
        let miles = PeakVolumeDraft(measure: .distance, text: "10", distanceSystem: .imperial).value
        #expect(miles != nil && abs(miles! - 16_093.44) < 0.001)
    }

    @Test("duration is in hours, held as seconds")
    func duration() {
        #expect(PeakVolumeDraft(measure: .duration, text: "7.5").value == 27_000)
        #expect(PeakVolumeDraft(measure: .trimp, text: "450").value == 450)
    }

    @Test("zero, negative, text and infinity are invalid", arguments: ["0", "-5", "abc", "inf", "nan", "1.2.3"])
    func invalid(text: String) {
        let draft = PeakVolumeDraft(measure: .trimp, text: text)
        #expect(draft.validation == .invalid)
        #expect(draft.value == nil)
        #expect(draft.message != nil)
    }

    @Test("more than a week can hold is refused per measure")
    func tooLarge() {
        #expect(PeakVolumeDraft(measure: .distance, text: "501", distanceSystem: .metric).validation == .tooLarge)
        #expect(PeakVolumeDraft(measure: .distance, text: "500", distanceSystem: .metric).validation == .valid)
        #expect(PeakVolumeDraft(measure: .duration, text: "41").validation == .tooLarge)
        #expect(PeakVolumeDraft(measure: .trimp, text: "5001").validation == .tooLarge)
    }

    @Test("changing the measure clears the text, keeping it when unchanged")
    func measureChange() {
        var draft = PeakVolumeDraft(measure: .distance, text: "60")
        draft.setMeasure(.distance)
        #expect(draft.text == "60")
        draft.setMeasure(.duration)
        #expect(draft.text.isEmpty)
        #expect(draft.unitLabel == "h")
    }
}
