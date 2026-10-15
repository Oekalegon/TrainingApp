import Foundation
import TrainingCore

/// Drives the "Add Race" sheet (MVP2-17): name, date, and priority for a target ``Race``, then
/// saves it into ``TrainingModel``.
///
/// Editing/deleting an existing race and the calendar/library entry points that would present this
/// sheet (MVP2-21's library tab, MVP2-22's calendar "+") are separate, later tickets — this view
/// model only creates new races.
@Observable
@MainActor
public final class RaceSheetViewModel {
    private let model: TrainingModel

    /// The race's display name, as typed. Never trimmed while editing — only ``save()`` trims it
    /// to decide whether it's actually blank.
    public var name: String = ""
    /// The calendar day the race takes place, in the athlete's timezone.
    public var date: Date
    public var priority: RacePriority = .primary

    /// Set when ``save()`` fails — a store failure. The sheet shows this as a blocking alert.
    public private(set) var saveError: String?
    public private(set) var isSaving = false

    /// Whether ``save()`` has something to save: a non-blank name.
    public var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Creates a race sheet view model.
    ///
    /// - Parameters:
    ///   - model: The training model to save the race into.
    ///   - date: The day the race takes place; defaults to `.now`'s calendar day.
    public init(model: TrainingModel, date: Date = .now) {
        self.model = model
        self.date = date
    }

    private var athleteCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.athlete.timeZone
        return calendar
    }

    /// The earliest day the sheet's `DatePicker` may select — today, in the athlete's calendar.
    /// Matches ``PlannedWorkoutSheetViewModel/minimumDate(asOf:)``'s day-boundary semantics.
    ///
    /// - Parameter today: Injected rather than read from `.now` internally, matching
    ///   `PlannedWorkoutSheetViewModel`'s own convention, so a test can pin an exact boundary
    ///   instead of racing `.now`.
    public func minimumDate(asOf today: Date = .now) -> Date {
        athleteCalendar.startOfDay(for: today)
    }

    /// Saves the race — `true` on success, in which case the sheet dismisses; `false` leaves
    /// ``saveError`` set for the sheet to show.
    @discardableResult
    public func save() async -> Bool {
        // Guards against a double-tap landing before the `Task` wrapping this call has actually
        // started running, which would otherwise create two separate races for one tap.
        guard !isSaving else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        isSaving = true
        defer { isSaving = false }
        // Normalized to the athlete calendar's start of day: `date` itself can carry whatever
        // time-of-day the sheet's `DatePicker` happened to start from (its `.date`-only
        // `displayedComponents` only constrains what's *editable*, not what's already in the
        // bound value) -- WeekViewModel's own day grouping tolerates that by comparing with
        // `isDate(_:inSameDayAs:)` everywhere, but `PlanEvaluator`'s race-day TSB rule looks a
        // race's `date` up as an exact dictionary key against `FitnessMetrics.day` (itself always
        // a start-of-day value), so an unnormalized `date` here would silently never match and
        // the guardrail would never fire (MVP2-18).
        let race = Race(name: trimmedName, date: athleteCalendar.startOfDay(for: date), priority: priority)
        do {
            try await model.add(race)
            return true
        } catch {
            saveError = "Couldn't save this race: \(error.localizedDescription)"
            return false
        }
    }
}
