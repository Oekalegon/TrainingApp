import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// MVP5-112: the run type picker follows TrainingKit's rules for the micro length.
@MainActor
@Suite("RunTypePickerViewModel")
struct RunTypePickerViewModelTests {
    @Test("rows follow the micro length, and unsupported lengths are refused")
    func days() {
        let model = RunTypePickerViewModel(microLength: 10)
        #expect(model.days == Array(0..<10))
        model.setMicroLength(14)
        #expect(model.days.count == 14)
        model.setMicroLength(9)
        #expect(model.microLength == 14)
        #expect(RunTypePickerViewModel(microLength: 5).microLength == 7)
    }

    @Test("weekdays show for 7 and 14 days but not 10")
    func weekdays() {
        let model = RunTypePickerViewModel(microLength: 7, firstWeekday: .saturday)
        #expect(model.weekdayName(forDay: 0) == "Saturday")
        #expect(model.weekdayName(forDay: 2) == "Monday")
        model.setMicroLength(14)
        #expect(model.weekdayName(forDay: 8) == "Sunday")
        model.setMicroLength(10)
        #expect(model.weekdayName(forDay: 0) == nil)
        #expect(model.title(forDay: 0) == "Day 1")
        #expect(model.accessibilityTitle(forDay: 3) == "Day 4")
        #expect(RunTypePickerViewModel(microLength: 7).weekdayName(forDay: 0) == nil)
    }

    @Test("several types can be named for a day and toggled off")
    func toggle() {
        let model = RunTypePickerViewModel(microLength: 7)
        model.toggle(.interval, onDay: 3)
        model.toggle(.threshold, onDay: 3)
        #expect(model.namedTypes(onDay: 3) == [.threshold, .interval])
        model.toggle(.interval, onDay: 3)
        #expect(model.namedTypes(onDay: 3) == [.threshold])
        model.toggle(.threshold, onDay: 3)
        #expect(model.preferences.dayRunTypes.isEmpty)
        #expect(!model.hasNamedTypes)
    }

    @Test("clearing a day makes it unspecified")
    func clear() {
        let model = RunTypePickerViewModel(microLength: 7)
        model.toggle(.long, onDay: 6)
        model.toggle(.easy, onDay: 1)
        model.clear(day: 6)
        #expect(model.namedTypes(onDay: 6).isEmpty)
        #expect(model.namedTypes(onDay: 1) == [.easy])
    }

    @Test("a named type is tied to its days, the rest are free")
    func allowed() {
        let model = RunTypePickerViewModel(microLength: 7)
        model.toggle(.long, onDay: 6)
        #expect(!model.allowedTypes(onDay: 0).contains(.long))
        #expect(model.allowedTypes(onDay: 6).contains(.long))
        #expect(model.allowedTypes(onDay: 0).contains(.threshold))
    }

    @Test("shortening the micro drops days from the result but changing back restores them")
    func lengthChange() {
        let model = RunTypePickerViewModel(microLength: 14)
        model.toggle(.long, onDay: 12)
        model.toggle(.easy, onDay: 2)
        model.setMicroLength(7)
        #expect(Set(model.preferences.dayRunTypes.keys) == [2])
        #expect(model.hiddenDayCount == 1)
        model.setMicroLength(14)
        #expect(Set(model.preferences.dayRunTypes.keys) == [2, 12])
        #expect(model.hiddenDayCount == 0)
    }

    @Test("availability in the preferences is carried through")
    func availability() {
        var start = PlanPreferences()
        start.runAvailability = RunAvailability().togglingDay(.monday)
        let model = RunTypePickerViewModel(preferences: start)
        model.toggle(.easy, onDay: 0)
        #expect(model.preferences.runAvailability == start.runAvailability)
    }
}

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

/// MVP5-112: the interim on-device store for the athlete's run types.
@MainActor
@Suite("AthleteRunTypesStore")
struct AthleteRunTypesStoreTests {
    private func store() -> AthleteRunTypesStore {
        let defaults = UserDefaults(suiteName: "AthleteRunTypesStoreTests-\(UUID().uuidString)")!
        return AthleteRunTypesStore(defaults: defaults)
    }

    @Test("nothing saved gives no run types and 7 days")
    func empty() {
        let loaded = store().load()
        #expect(loaded.preferences.dayRunTypes.isEmpty)
        #expect(loaded.microLength == 7)
    }

    @Test("run types and length round-trip, keeping days beyond the length")
    func roundTrip() {
        let store = store()
        var preferences = PlanPreferences()
        preferences.setRunTypes([.long, .easy], onDay: 12)
        store.save(preferences, microLength: 10)
        let loaded = store.load()
        #expect(loaded.preferences.dayRunTypes == [12: [.long, .easy]])
        #expect(loaded.microLength == 10)
    }
}
