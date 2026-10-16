import TrainingCore

/// The edits the Running Availability section of the Calendar screen makes (MVP5-105), as pure functions of the value so
/// they're tested without a view. The screen applies one, shows the result at once and saves it
/// through ``MicroCycleViewModel/setRunAvailability(_:asOf:)``.
extension RunAvailability {
    /// Whether the athlete can run on `weekday` in any slot.
    func isAvailable(on weekday: Weekday) -> Bool {
        !self[weekday].isEmpty
    }

    /// The availability with `weekday` selected or cleared. Selecting a day allows all three parts
    /// of the day (the athlete may switch some off); clearing it removes the day.
    func togglingDay(_ weekday: Weekday) -> RunAvailability {
        var copy = self
        copy[weekday] = isAvailable(on: weekday) ? [] : Set(DaySlot.allCases)
        return copy
    }

    /// The availability with `slot` switched on or off for `weekday` (MVP5-130). Turning off the last
    /// part of a day clears the day, so a day is never selected with nothing to run in; the screen
    /// then shows its switch off. Turning a part on for a day that is off selects the day with just
    /// that part.
    func togglingSlot(_ slot: DaySlot, on weekday: Weekday) -> RunAvailability {
        var copy = self
        var slots = self[weekday]
        if slots.contains(slot) { slots.remove(slot) } else { slots.insert(slot) }
        copy[weekday] = slots
        return copy
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

extension DaySlot {
    /// The label for the part of the day: "Morning", "Afternoon", "Evening".
    var displayName: String {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        }
    }
}
