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

/// The plan's micro-cycles with their periods precomputed, so the render and swipe paths don't sort
/// or run calendar arithmetic per lookup. Rebuilt only when the cycles or the time zone change.
struct PlanIndex {
    /// A micro-cycle and the period it covers, earliest first.
    struct Entry {
        let cycle: TrainingCycle
        let period: DisplayPeriod
    }

    /// What this index was built from; see `WeekViewModel.planIndex()`.
    let key: Int
    let micros: [Entry]
    let byID: [UUID: TrainingCycle]
}

extension WeekViewModel {
    /// The index of the plan's micro-cycles, rebuilt only when `model.cycles`, the cycles peeked from
    /// the store (see ``peekCycles()``) or the athlete's time zone changed.
    func planIndex() -> PlanIndex {
        var cycles = model.cycles
        let known = Set(cycles.map(\.id))
        cycles += peekedCycles.filter { !known.contains($0.id) }
        var hasher = Hasher()
        hasher.combine(model.athlete.timeZone.identifier)
        for cycle in cycles {
            hasher.combine(cycle.id)
            hasher.combine(cycle.dateRange.lowerBound)
            hasher.combine(cycle.dateRange.upperBound)
            hasher.combine(cycle.level)
        }
        let key = hasher.finalize()
        if let cached = planIndexCache, cached.key == key { return cached }
        let calendar = self.calendar
        let micros = cycles
            .filter { $0.level == .micro }
            .map { micro -> PlanIndex.Entry in
                let start = calendar.startOfDay(for: micro.dateRange.lowerBound)
                let last = calendar.startOfDay(for: micro.dateRange.upperBound)
                let days = calendar.dateComponents([.day], from: start, to: last).day ?? 0
                return PlanIndex.Entry(cycle: micro, period: DisplayPeriod(start: start, lengthInDays: days + 1))
            }
            .sorted { $0.period.start < $1.period.start }
        let index = PlanIndex(
            key: key, micros: micros, byID: Dictionary(cycles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        )
        planIndexCache = index
        return index
    }

    /// The micro-cycle containing `day`, if the plan has one.
    func micro(containing day: Date) -> TrainingCycle? {
        planEntry(containing: day, in: planIndex())?.cycle
    }

    private func planEntry(containing day: Date, in index: PlanIndex) -> PlanIndex.Entry? {
        let day = calendar.startOfDay(for: day)
        return index.micros.first { $0.period.start <= day && day <= $0.period.lastDay(calendar: calendar) }
    }

    /// The period shown for `date`: the planned micro-cycle containing it (7, 10, 14 days, …), else
    /// the calendar week containing it, cut short where a micro starts or ends so periods never
    /// overlap. Every date lies in exactly one period, which is what makes paging consistent.
    func period(containing date: Date) -> DisplayPeriod {
        let index = planIndex()
        if let entry = planEntry(containing: date, in: index) { return entry.period }
        let calendar = self.calendar
        let week = DisplayPeriod.calendarWeek(containing: date, calendar: calendar)
        let day = calendar.startOfDay(for: date)
        var start = week.start
        var last = week.lastDay(calendar: calendar)
        for entry in index.micros {
            let micro = entry.period
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

    /// Fetches the cycles around ``anchorDate`` from the store, so the micro containing it (and its
    /// neighbors' lengths) are known before the first `model.load`: a cold start inside a plan then
    /// loads the right range once instead of loading a calendar week and switching afterwards.
    func peekCycles() async {
        let calendar = self.calendar
        let day = calendar.startOfDay(for: anchorDate)
        guard let from = calendar.date(byAdding: .day, value: -45, to: day),
              let to = calendar.date(byAdding: .day, value: 45, to: day),
              let cycles = try? await model.stores.cycleStore.cycles(in: from...to)
        else { return }
        peekedCycles = cycles
    }

    /// Fetches the whole of the displayed micro's macro-cycle from the cycle store and records the
    /// order of its micro-cycles, for ``CycleContext/weekInPlan``. Only the cycles near the displayed
    /// period are in `model.cycles`, so counting there would number a micro from the edge of the
    /// loaded window. Run from ``refreshWeekCachesIfNeeded(asOf:activitiesChanged:)``, so a change to
    /// the plan renumbers too.
    func refreshMicroOrder() async {
        let index = planIndex()
        guard let micro = micro(containing: displayedWeekStart),
              let meso = micro.parentID.flatMap({ index.byID[$0] }),
              let macro = meso.level == .macro ? meso : meso.parentID.flatMap({ index.byID[$0] }),
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

    /// Where the period starting `weekStart` (default: the displayed one) sits in the plan, or `nil`
    /// when it isn't a planned micro-cycle.
    public func cycleContext(for weekStart: Date? = nil) -> CycleContext? {
        let index = planIndex()
        guard let entry = planEntry(containing: weekStart ?? displayedWeekStart, in: index) else { return nil }
        let micro = entry.cycle
        let parent = micro.parentID.flatMap { index.byID[$0] }
        let macro = parent?.level == .macro ? parent : parent?.parentID.flatMap { index.byID[$0] }
        let meso = parent?.level == .meso ? parent : nil
        let weekInPlan = macro
            .flatMap { microOrderByMacro[$0.id] }
            .flatMap { $0.firstIndex(of: micro.id) }
            .map { $0 + 1 }
        return CycleContext(
            macroName: macro?.name, mesoName: meso?.name, microName: micro.name, phase: micro.phase,
            loadRole: micro.loadRole, weekInPlan: weekInPlan, lengthInDays: entry.period.lengthInDays
        )
    }

    /// The title for the week view: "Micro N" with N the micro's position in the plan (also for a
    /// 7-day micro; just "Micro" until the position is known), else "Week N" for the calendar week of
    /// the year (MVP1-56).
    public var displayedTitle: String {
        guard let context = cycleContext() else { return "Week \(displayedWeekOfYear)" }
        return context.weekInPlan.map { "Micro \($0)" } ?? "Micro"
    }
}
