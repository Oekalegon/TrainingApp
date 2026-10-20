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
    /// maximum number of runs goes back to the default of 1 (MVP5-132) and the track to unavailable (MVP5-128), so a day
    /// switched on again never comes back with an earlier choice.
    func togglingDay(_ weekday: Weekday) -> RunAvailability {
        var copy = self
        copy[weekday] = isAvailable(on: weekday) ? [] : Set(DaySlot.allCases)
        copy.setRuns(1, on: weekday)
        // Track goes back to the default too (MVP5-128), so a day switched on again starts clean.
        copy = copy.settingTrack(false, on: weekday)
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
        if slots.isEmpty {
            copy.setRuns(1, on: weekday)
            copy = copy.settingTrack(false, on: weekday)
        }
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

extension RunAvailability {
    /// The availability with `type` named for `weekday`, or no longer named when it already is (MVP5-112). Naming a
    /// type ties it to the weekdays that name it (TrainingKit, ``runTypes(on:)``), so the types a day shows as
    /// chosen are only the ones it names, not the free ones the plan may add.
    func togglingRunType(_ type: RunType, on weekday: Weekday) -> RunAvailability {
        var copy = self
        var types = dayRunTypes[weekday] ?? []
        if types.contains(type) { types.remove(type) } else { types.insert(type) }
        copy.setRunTypes(types, on: weekday)
        return copy
    }

    /// The availability with no run type named for `weekday`, so the plan chooses.
    func clearingRunTypes(on weekday: Weekday) -> RunAvailability {
        var copy = self
        copy.setRunTypes([], on: weekday)
        return copy
    }
}

extension RunAvailability {
    /// Whether a track is available on `weekday` (MVP5-128). TrainingKit stores it per part of the day
    /// (``SlotOptions/trackAvailable``) but the screen asks it per day, so the day counts as having a track
    /// when any of its selected parts has one. Parts that are off are ignored.
    func hasTrack(on weekday: Weekday) -> Bool {
        self[weekday].contains { self[weekday, $0].trackAvailable }
    }

    /// The availability with a track available or not on `weekday` (MVP5-128): sets ``SlotOptions/trackAvailable``
    /// on all three parts of the day, also the ones that are off, so the choice holds when parts are switched on
    /// later. The other slot options (``SlotOptions/longRunPossible``) are left as they are; the screen does not
    /// offer them, since the "Long" run type already says which days take a long run.
    func settingTrack(_ isOn: Bool, on weekday: Weekday) -> RunAvailability {
        var copy = self
        for slot in DaySlot.allCases {
            var options = copy[weekday, slot]
            options.trackAvailable = isOn
            copy[weekday, slot] = options
        }
        return copy
    }
}

extension RunAvailability {
    /// The line under a weekday in the Running Availability list: "Off", or the parts of the day, the number
    /// of runs when above one and the run types named, e.g. "Morning, Evening · 2 runs · Interval, Threshold".
    func summary(on weekday: Weekday) -> String {
        guard isAvailable(on: weekday) else { return "Off" }
        var parts = [DaySlot.allCases.filter { self[weekday].contains($0) }.map(\.displayName).joined(separator: ", ")]
        let runs = runs(on: weekday)
        if runs > 1 { parts.append("\(runs) runs") }
        let types = RunType.allCases.filter { (dayRunTypes[weekday] ?? []).contains($0) }
        if !types.isEmpty { parts.append(types.map(\.displayName).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}
