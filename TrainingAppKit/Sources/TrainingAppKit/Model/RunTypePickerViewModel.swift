import Foundation
import TrainingCore

/// The state behind the per-micro-day run type picker (MVP5-112, MVP5 design doc §4a): the run types
/// the athlete names for each day of a plan's micro-cycle, for a micro of 7, 10 or 14 days.
///
/// Run types belong to a plan, not to the athlete: they describe the shape of the micro ("day 3 is a hard
/// day, day 7 is the long run"), so they are keyed by the 0-based micro day, as in
/// `PlanPreferences/dayRunTypes`. Several types can be named for a day. The view model follows TrainingKit's rules for the
/// micro length: changing it never throws entries away while editing (so changing back restores them),
/// and ``preferences`` is the result with the days that do not fit the length removed
/// (`PlanPreferences/validated(microLength:)`). Naming a type for a day ties it to the days that name
/// it; ``allowedTypes(onDay:)`` shows what the plan may therefore put on a day.
///
/// The host (the Create Plan wizard, later) owns one of these per plan and reads ``preferences`` when
/// it creates or saves the plan.
@Observable
@MainActor
final class RunTypePickerViewModel {
    /// The micro lengths the athlete can choose (design doc §3).
    static let supportedMicroLengths = [7, 10, 14]

    /// The run types named per day, including entries beyond the current micro length that are kept
    /// while editing. Read the result for the plan through ``preferences``.
    private(set) var draft: PlanPreferences

    /// The micro length in days, always one of ``supportedMicroLengths``.
    private(set) var microLength: Int

    /// The weekday of micro day 0, for 7- and 14-day micros, where a micro is whole weeks. `nil` when the plan's start is
    /// not known yet; the rows then say "Day n" only.
    let firstWeekday: Weekday?

    /// - Parameters:
    ///   - preferences: The preferences being edited (their availability is carried through unchanged).
    ///   - microLength: The micro length in days; an unsupported value becomes 7.
    ///   - firstWeekday: The weekday micro day 0 falls on, if known.
    init(preferences: PlanPreferences = PlanPreferences(), microLength: Int = 7, firstWeekday: Weekday? = nil) {
        draft = preferences
        self.microLength = Self.supportedMicroLengths.contains(microLength) ? microLength : 7
        self.firstWeekday = firstWeekday
    }

    /// The 0-based micro days, one row each.
    var days: [Int] { Array(0..<microLength) }

    /// The preferences for the plan: the edited ones without the days beyond the micro length.
    var preferences: PlanPreferences { draft.validated(microLength: microLength) }

    /// Whether rows show weekday names: only for 7- and 14-day micros, whose days repeat the same
    /// weekdays every micro. A 10-day micro drifts across the week, so a weekday would be wrong.
    var showsWeekdays: Bool { firstWeekday != nil && microLength != 10 }

    /// The label of a row: "Day 1" for every micro.
    func title(forDay day: Int) -> String { "Day \(day + 1)" }

    /// The weekday name of a micro day, for 7- and 14-day micros; `nil` for 10-day micros or without a start.
    func weekdayName(forDay day: Int) -> String? {
        guard showsWeekdays, let first = firstWeekday else { return nil }
        let all = Weekday.allCases
        let start = all.firstIndex(of: first) ?? 0
        return all[(start + day) % all.count].displayName
    }

    /// The row's full label for VoiceOver: "Day 1, Monday" or "Day 4".
    func accessibilityTitle(forDay day: Int) -> String {
        [title(forDay: day), weekdayName(forDay: day)].compactMap { $0 }.joined(separator: ", ")
    }

    /// The run types named for a day, ordered like `RunType.allCases`.
    func namedTypes(onDay day: Int) -> [RunType] {
        let named = draft.dayRunTypes[day] ?? []
        return RunType.allCases.filter(named.contains)
    }

    /// Whether `type` is named for `day`.
    func isNamed(_ type: RunType, onDay day: Int) -> Bool { draft.dayRunTypes[day]?.contains(type) ?? false }

    /// The types the plan may place on a day: those it names plus those no day names.
    func allowedTypes(onDay day: Int) -> [RunType] {
        let allowed = draft.runTypes(onDay: day, microLength: microLength)
        return RunType.allCases.filter(allowed.contains)
    }

    /// Names `type` for `day`, or stops naming it when it already is.
    func toggle(_ type: RunType, onDay day: Int) {
        var types = draft.dayRunTypes[day] ?? []
        if types.contains(type) { types.remove(type) } else { types.insert(type) }
        draft.setRunTypes(types, onDay: day)
    }

    /// Stops naming any type for `day`, which makes it unspecified again.
    func clear(day: Int) { draft.setRunTypes([], onDay: day) }

    /// Whether any day names a type.
    var hasNamedTypes: Bool { !preferences.dayRunTypes.isEmpty }

    /// Changes the micro length. Entries beyond the new length stay in ``draft`` until the athlete
    /// changes back, but are not in ``preferences``.
    ///
    /// - Parameter length: 7, 10 or 14; anything else is ignored.
    func setMicroLength(_ length: Int) {
        guard Self.supportedMicroLengths.contains(length) else { return }
        microLength = length
    }

    /// The number of named days that do not fit the current length and so are left out of ``preferences``.
    var hiddenDayCount: Int { draft.dayRunTypes.keys.filter { $0 >= microLength }.count }
}
