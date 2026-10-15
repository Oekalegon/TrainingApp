import Foundation
import TrainingCore

/// Where a displayed period sits in the plan, for the week view's header (MVP5-107).
public struct CycleContext: Hashable, Sendable {
    /// The macro-cycle's name, e.g. "Ultra prep 2027", when the micro hangs under one.
    public let macroName: String?
    /// The meso-cycle's name, e.g. "Build 2", when the micro hangs under one.
    public let mesoName: String?
    /// The micro-cycle's own name, e.g. "Week 11".
    public let microName: String
    /// The micro's phase; show it by its `id`, never switch exhaustively on it.
    public let phase: CyclePhase
    /// How hard the micro is meant to be.
    public let loadRole: MicroLoadRole?
    /// The micro's 1-based position (its "Micro N") among the macro's micro-cycles; `nil` without a macro.
    public let weekInPlan: Int?
    /// The micro's length in days (7, 10, 14, …).
    public let lengthInDays: Int

    /// "Macro › Meso › Micro", leaving out whatever level the micro doesn't have.
    public var breadcrumb: String {
        [macroName, mesoName, microName].compactMap { $0 }.joined(separator: " › ")
    }

    /// The phase as a title, e.g. "Build".
    public var phaseTitle: String { phase.id.capitalized }
}

extension WeekViewModel {
    /// The planned micro-cycles loaded into `model`, earliest first.
    private var microcycles: [TrainingCycle] {
        model.cycles.filter { $0.level == .micro }.sorted { $0.dateRange.lowerBound < $1.dateRange.lowerBound }
    }

    /// The micro's first day and length in the athlete's calendar (its range is day-granular).
    private func period(of micro: TrainingCycle) -> DisplayPeriod {
        let start = calendar.startOfDay(for: micro.dateRange.lowerBound)
        let last = calendar.startOfDay(for: micro.dateRange.upperBound)
        let days = calendar.dateComponents([.day], from: start, to: last).day ?? 0
        return DisplayPeriod(start: start, lengthInDays: days + 1)
    }

    /// The micro-cycle containing `day`, if the plan has one.
    func micro(containing day: Date) -> TrainingCycle? {
        let day = calendar.startOfDay(for: day)
        return microcycles.first {
            calendar.startOfDay(for: $0.dateRange.lowerBound) <= day && day <= calendar.startOfDay(for: $0.dateRange.upperBound)
        }
    }

    /// The period shown for `date`: the planned micro-cycle containing it (7, 10, 14 days, …), else
    /// the calendar week containing it, cut short where a micro starts or ends so periods never
    /// overlap. Every date lies in exactly one period, which is what makes paging consistent.
    func period(containing date: Date) -> DisplayPeriod {
        if let micro = micro(containing: date) { return period(of: micro) }
        let week = DisplayPeriod.calendarWeek(containing: date, calendar: calendar)
        let day = calendar.startOfDay(for: date)
        var start = week.start
        var last = week.lastDay(calendar: calendar)
        for micro in microcycles {
            let micro = period(of: micro)
            if micro.lastDay(calendar: calendar) < day {
                if let after = calendar.date(byAdding: .day, value: 1, to: micro.lastDay(calendar: calendar)) { start = max(start, after) }
            } else if micro.start > day, let before = calendar.date(byAdding: .day, value: -1, to: micro.start) {
                last = min(last, before)
            }
        }
        let days = calendar.dateComponents([.day], from: start, to: last).day ?? 0
        return DisplayPeriod(start: start, lengthInDays: days + 1)
    }

    /// The period that follows `period`, from the plan: it may differ in length from `period`.
    func nextPeriod(of period: DisplayPeriod) -> DisplayPeriod {
        let after = calendar.date(byAdding: .day, value: period.lengthInDays, to: period.start) ?? period.start
        return self.period(containing: after)
    }

    /// The period that precedes `period`, from the plan: it may differ in length from `period`.
    func previousPeriod(of period: DisplayPeriod) -> DisplayPeriod {
        let before = calendar.date(byAdding: .day, value: -1, to: period.start) ?? period.start
        return self.period(containing: before)
    }

    /// The period `offset` periods from the displayed one (negative for earlier).
    func period(offset: Int) -> DisplayPeriod {
        var period = displayedPeriod
        for _ in 0..<abs(offset) {
            period = offset > 0 ? nextPeriod(of: period) : previousPeriod(of: period)
        }
        return period
    }

    /// Fetches the whole of the displayed micro's macro-cycle from the cycle store and records the
    /// order of its micro-cycles, for ``CycleContext/weekInPlan``.
    func refreshMicroOrder() async {
        guard let micro = micro(containing: displayedWeekStart) else { return }
        let loaded = Dictionary(model.cycles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard let meso = micro.parentID.flatMap({ loaded[$0] }),
              let macro = meso.level == .macro ? meso : meso.parentID.flatMap({ loaded[$0] }),
              let all = try? await model.stores.cycleStore.cycles(in: macro.dateRange)
        else { return }
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = all.filter { candidate in
            guard candidate.level == .micro, let parent = candidate.parentID.flatMap({ byID[$0] }) else { return false }
            return parent.id == macro.id || parent.parentID == macro.id
        }
        .sorted { $0.dateRange.lowerBound < $1.dateRange.lowerBound }
        .map(\.id)
        if microOrderByMacro[macro.id] != ids { microOrderByMacro[macro.id] = ids }
    }

    /// Shows `period`, remembering its start as the date to keep resolving from.
    func show(_ period: DisplayPeriod) {
        anchorDate = period.start
        displayedWeekStart = period.start
        displayedLengthInDays = period.lengthInDays
    }

    /// Re-resolves the displayed period from the plan, after a load may have brought in the micro
    /// containing ``anchorDate``. A no-op when nothing changed.
    func refreshDisplayedPeriod() {
        let resolved = period(containing: anchorDate)
        guard resolved != displayedPeriod else { return }
        displayedWeekStart = resolved.start
        displayedLengthInDays = resolved.lengthInDays
    }

    /// Where the period starting `weekStart` (default: the displayed one) sits in the plan, or `nil`
    /// when it isn't a planned micro-cycle.
    public func cycleContext(for weekStart: Date? = nil) -> CycleContext? {
        guard let micro = micro(containing: weekStart ?? displayedWeekStart) else { return nil }
        let byID = Dictionary(model.cycles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let meso = micro.parentID.flatMap { byID[$0] }
        let macro = meso?.parentID.flatMap { byID[$0] } ?? (meso?.level == .macro ? meso : nil)
        let meso2 = meso?.level == .meso ? meso : nil
        let weekInPlan = macro
            .flatMap { microOrderByMacro[$0.id] }
            .flatMap { $0.firstIndex(of: micro.id) }
            .map { $0 + 1 }
        let range = period(of: micro)
        return CycleContext(
            macroName: macro?.name, mesoName: meso2?.name, microName: micro.name, phase: micro.phase,
            loadRole: micro.loadRole, weekInPlan: weekInPlan, lengthInDays: range.lengthInDays
        )
    }

    /// The title for the week view: "Micro N" with N the micro's position in the plan (also for
    /// a 7-day micro), else "Week N" for the calendar week of the year (MVP1-56).
    public var displayedTitle: String {
        if let number = cycleContext()?.weekInPlan { return "Micro \(number)" }
        return "Week \(displayedWeekOfYear)"
    }
}
