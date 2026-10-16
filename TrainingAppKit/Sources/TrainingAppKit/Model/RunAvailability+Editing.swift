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
    /// of the day (the athlete may switch some off); clearing it removes the day. Either way the
    /// maximum number of runs goes back to the default of 1 (MVP5-132), so a day switched on again
    /// never comes back with an earlier choice.
    func togglingDay(_ weekday: Weekday) -> RunAvailability {
        var copy = self
        copy[weekday] = isAvailable(on: weekday) ? [] : Set(DaySlot.allCases)
        copy.setRuns(1, on: weekday)
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
        // A cleared day starts again from the default of one run, like `togglingDay`.
        if slots.isEmpty { copy.setRuns(1, on: weekday) }
        return copy
    }

    /// The availability with the maximum number of runs on `weekday` set to `count` (MVP5-132). The number is
    /// stored as given and TrainingKit caps what is read (``runs(on:)``) at the day's free parts, so
    /// a number above the selected parts is not lost when parts are switched off and on again.
    func settingRuns(_ count: Int, on weekday: Weekday) -> RunAvailability {
        var copy = self
        copy.setRuns(count, on: weekday)
        return copy
    }

    /// The most runs the "Maximum number of runs" control offers on `weekday`: one per selected part,
    /// as the generator puts each run in its own part. At least 1, so a day that is off still has a valid range.
    func maxRuns(on weekday: Weekday) -> Int {
        max(self[weekday].count, 1)
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
