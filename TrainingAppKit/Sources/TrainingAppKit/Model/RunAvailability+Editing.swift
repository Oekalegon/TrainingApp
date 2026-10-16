import TrainingCore

/// The edits the Running Availability section of the Calendar screen makes (MVP5-105), as pure functions of the value so
/// they're tested without a view. The screen applies one, shows the result at once and saves it
/// through ``MicroCycleViewModel/setRunAvailability(_:asOf:)``.
extension RunAvailability {
    /// Whether the athlete can run on `weekday` in any slot.
    func isAvailable(on weekday: Weekday) -> Bool {
        !self[weekday].isEmpty
    }

    /// The availability with `weekday` selected or cleared. Selecting a day allows any time, which
    /// the athlete may narrow to one slot; clearing it removes the day.
    func togglingDay(_ weekday: Weekday) -> RunAvailability {
        var copy = self
        copy[weekday] = isAvailable(on: weekday) ? [] : Set(DaySlot.allCases)
        return copy
    }

    /// The availability with `weekday` narrowed to `choice`; the day stays selected.
    func settingSlots(_ choice: SlotChoice, on weekday: Weekday) -> RunAvailability {
        var copy = self
        copy[weekday] = choice.slots
        return copy
    }

    /// Which of the slot choices `weekday` has: both slots, or just one. A day that isn't selected
    /// counts as ``SlotChoice/anyTime``, the choice a day gets when it is selected.
    func slotChoice(on weekday: Weekday) -> SlotChoice {
        switch self[weekday] {
        case [.morning]: .morning
        case [.afternoonEvening]: .afternoonEvening
        default: .anyTime
        }
    }
}

extension Weekday {
    /// All seven weekdays in the order a week starting on `self` shows them.
    var weekOrder: [Weekday] {
        let all = Weekday.allCases
        let start = all.firstIndex(of: self) ?? 0
        return Array(all[start...] + all[..<start])
    }

    /// The three-letter label used in summaries: "Mon". Like ``displayName`` it is English only; both
    /// need localising together.
    var shortName: String {
        String(displayName.prefix(3))
    }
}

/// What a selected day offers (MVP5-105): usually any time, narrowed to one slot when the athlete can
/// only run in the morning or only in the afternoon / evening. Both slots (``anyTime``) also allows a
/// two-a-day.
enum SlotChoice: CaseIterable, Hashable {
    case anyTime, morning, afternoonEvening

    /// The slots this choice allows.
    var slots: Set<DaySlot> {
        switch self {
        case .anyTime: Set(DaySlot.allCases)
        case .morning: [.morning]
        case .afternoonEvening: [.afternoonEvening]
        }
    }

    /// The label for the choice: "Any Time", "Morning", "Afternoon / Evening".
    var displayName: String {
        switch self {
        case .anyTime: "Any Time"
        case .morning: DaySlot.morning.displayName
        case .afternoonEvening: DaySlot.afternoonEvening.displayName
        }
    }

    /// A label short enough for a segmented control: "Any Time", "Morning", "Aft. / Eve.".
    var shortName: String {
        self == .afternoonEvening ? "Aft. / Eve." : displayName
    }
}

extension DaySlot {
    /// The label for the slot: "Morning", "Afternoon / Evening".
    var displayName: String {
        switch self {
        case .morning: "Morning"
        case .afternoonEvening: "Afternoon / Evening"
        }
    }
}
