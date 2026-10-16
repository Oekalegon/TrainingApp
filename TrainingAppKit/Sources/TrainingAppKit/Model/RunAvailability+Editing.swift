import TrainingCore

/// The edits the Running Availability screen makes (MVP5-105), as pure functions of the value so
/// they're tested without a view. The screen applies one, shows the result at once and saves it
/// through ``MicroCycleViewModel/setRunAvailability(_:asOf:)``.
extension RunAvailability {
    /// Whether the athlete can run on `weekday` in any slot.
    func isAvailable(on weekday: Weekday) -> Bool {
        !self[weekday].isEmpty
    }

    /// The availability with `weekday` selected or cleared. Selecting a day offers every slot, which
    /// the athlete then narrows; clearing it removes the day.
    func togglingDay(_ weekday: Weekday) -> RunAvailability {
        var copy = self
        copy[weekday] = isAvailable(on: weekday) ? [] : Set(DaySlot.allCases)
        return copy
    }

    /// The availability with `slot` switched on or off for `weekday`. Switching off a day's last
    /// slot clears the day, since a day without slots is no running day.
    func togglingSlot(_ slot: DaySlot, on weekday: Weekday) -> RunAvailability {
        var copy = self
        if copy[weekday].contains(slot) {
            copy[weekday].remove(slot)
        } else {
            copy[weekday].insert(slot)
        }
        return copy
    }

    /// The weekdays the athlete can run on, ordered by calendar weekday starting from Sunday.
    var availableWeekdays: [Weekday] {
        Weekday.allCases.filter(isAvailable(on:))
    }
}

extension Weekday {
    /// All seven weekdays in the order a week starting on `self` shows them.
    var weekOrder: [Weekday] {
        let all = Weekday.allCases
        let start = all.firstIndex(of: self) ?? 0
        return Array(all[start...] + all[..<start])
    }

    /// The three-letter label used in summaries: "Mon".
    var shortName: String {
        String(displayName.prefix(3))
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
