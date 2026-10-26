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
    /// The distance chosen from the usual race distances, or ``RaceDistancePreset/custom`` to type one in ``customDistanceText``.
    public var distancePreset: RaceDistancePreset = .marathon
    /// The distance typed for ``RaceDistancePreset/custom``, in kilometres or miles by ``distanceSystem``.
    public var customDistanceText: String = ""
    /// Whether the custom distance is typed in kilometres or miles.
    public var distanceSystem: DistanceSystem = .deviceDefault

    /// Set when ``save()`` fails — a store failure. The sheet shows this as a blocking alert.
    public private(set) var saveError: String?
    public private(set) var isSaving = false
    /// The race ``save()`` last stored, so a caller that opened this sheet for a new race (the Create Plan wizard) can select it.
    public private(set) var lastSavedRace: Race?

    /// The race distance in meters: the preset's, or the typed custom one; `nil` while the custom text is not a positive number.
    public var distanceMeters: Double? {
        if let meters = distancePreset.meters { return meters }
        let trimmed = customDistanceText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard trimmed.wholeMatch(of: /[0-9]*\.?[0-9]+|[0-9]+\./) != nil, let number = Double(trimmed), number > 0 else { return nil }
        let meters = number * (distanceSystem == .metric ? 1000 : 1609.344)
        return meters.isFinite && meters <= RaceDistancePreset.maximumMeters ? meters : nil
    }

    /// Whether ``save()`` has something to save: a non-blank name and a valid distance.
    public var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && distanceMeters != nil }

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
        guard !trimmedName.isEmpty, let distanceMeters else { return false }
        isSaving = true
        defer { isSaving = false }
        // Normalized to the athlete calendar's start of day: `date` itself can carry whatever
        // time-of-day the sheet's `DatePicker` happened to start from (its `.date`-only
        // `displayedComponents` only constrains what's *editable*, not what's already in the
        // bound value) -- MicroCycleViewModel's own day grouping tolerates that by comparing with
        // `isDate(_:inSameDayAs:)` everywhere, but `PlanEvaluator`'s race-day TSB rule looks a
        // race's `date` up as an exact dictionary key against `FitnessMetrics.day` (itself always
        // a start-of-day value), so an unnormalized `date` here would silently never match and
        // the guardrail would never fire (MVP2-18).
        let race = Race(name: trimmedName, date: athleteCalendar.startOfDay(for: date), priority: priority, distanceMeters: distanceMeters)
        do {
            try await model.add(race)
            lastSavedRace = race
            return true
        } catch {
            saveError = "Couldn't save this race: \(error.localizedDescription)"
            return false
        }
    }
}

/// The usual race distances offered when adding a race, and a custom one.
public enum RaceDistancePreset: String, CaseIterable, Identifiable, Sendable {
    case fiveK, tenK, halfMarathon, marathon, fiftyK, hundredK, custom

    public var id: String { rawValue }

    /// The most a race can be, in meters (a 1000 km ultra), so a typo does not make a nonsense race.
    public static let maximumMeters = 1_000_000.0

    /// The distance in meters; `nil` for ``custom``.
    public var meters: Double? {
        switch self {
        case .fiveK: 5000
        case .tenK: 10_000
        case .halfMarathon: 21_097.5
        case .marathon: Race.marathonDistanceMeters
        case .fiftyK: 50_000
        case .hundredK: 100_000
        case .custom: nil
        }
    }

    /// The name shown in the picker.
    public var title: String {
        switch self {
        case .fiveK: "5K"
        case .tenK: "10K"
        case .halfMarathon: "Half marathon"
        case .marathon: "Marathon"
        case .fiftyK: "50K"
        case .hundredK: "100K"
        case .custom: "Other…"
        }
    }
}
