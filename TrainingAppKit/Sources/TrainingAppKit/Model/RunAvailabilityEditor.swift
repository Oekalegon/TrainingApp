import Foundation
import TrainingCore

/// The state behind the Running Availability section of the Calendar screen (MVP5-105): the availability the athlete is
/// editing, shown at once while it saves, and whether the last save failed.
///
/// Each change is applied to what is shown, so quick successive toggles compose, and then saved
/// through `save`. The shown choice is given up for the saved availability only when the latest
/// save is done: if that save failed the screen goes back to what is saved and ``didFail`` is set;
/// an earlier failed save is covered by the later one, which carries its change too.
@Observable
@MainActor
final class RunAvailabilityEditor {
    /// The availability just chosen, while a save is outstanding.
    private var pending: RunAvailability?
    /// Counts the changes made, so only the latest save gives up the shown choice.
    private var changeCount = 0
    /// Whether a save failed and the screen should say so; the screen clears it when dismissed.
    var didFail = false

    private let saved: () -> RunAvailability
    private let save: (RunAvailability) async -> Bool

    /// - Parameters:
    ///   - saved: The availability currently on the profile.
    ///   - save: Saves an availability, returning whether it was saved.
    init(saved: @escaping () -> RunAvailability, save: @escaping (RunAvailability) async -> Bool) {
        self.saved = saved
        self.save = save
    }

    /// What the screen shows: the pending choice, else what is saved.
    var shown: RunAvailability { pending ?? saved() }

    /// Selects `weekday` (with all three parts) or clears it, and saves.
    func toggleDay(_ weekday: Weekday) async {
        await apply { $0.togglingDay(weekday) }
    }

    /// Switches `slot` on or off for `weekday` and saves; switching off the last part clears the day.
    func toggleSlot(_ slot: DaySlot, on weekday: Weekday) async {
        await apply { $0.togglingSlot(slot, on: weekday) }
    }

    private func apply(_ change: (RunAvailability) -> RunAvailability) async {
        let updated = change(shown)
        pending = updated
        changeCount += 1
        let current = changeCount
        if await !save(updated) { didFail = true }
        guard current == changeCount else { return }
        pending = nil
    }
}
