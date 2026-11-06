import Foundation
import TrainingCore

/// Everything ``WorkoutRanker/rank(day:replacing:plan:workouts:templates:cycles:activities:races:athlete:paradigm:targetRace:guardrails:microSeconds:today:)``
/// reads, read from the stores so the ranking can run off the main actor (MVP5-156).
struct WorkoutRankingInput: Sendable {
    var day: Date
    var replacing: PlannedActivity?
    var plan: [PlannedActivity]
    var workouts: [StructuredWorkout]
    var templates: [WorkoutTemplate]
    var cycles: [TrainingCycle]
    var activities: [Activity]
    var races: [Race]
    var athlete: AthleteProfile
    var microSeconds: TimeInterval?
    var today: Date

    /// Ranks with TrainingKit's ranker. The plan's paradigm and target race are not stored with a plan, so the ranker
    /// applies no paradigm rules: it still judges form, monotony, strain, the race-day form and the neighbours'
    /// own recovery days.
    func rank() async throws -> [RankedWorkout] {
        try await WorkoutRanker.rank(
            day: day, replacing: replacing, plan: plan, workouts: workouts, templates: templates, cycles: cycles,
            activities: activities, races: races, athlete: athlete, microSeconds: microSeconds, today: today
        )
    }
}

/// Drives the sheet that lists every workout for a day, best fit first (MVP5-156): the athlete adds a workout to a day or
/// replaces one, and sees all templates filled in and ranked by TrainingKit's ``WorkoutRanker`` with the reason a
/// workout ranks low and what it does to the form, the micro-cycle's time and the load. Any of them can be picked.
///
/// The ranking is CPU-bound (with no target it ranks about 9,000 variants), so it runs off the main actor and is
/// cancelled with the sheet. A workout that doesn't suit is listed low, with its reasons, and never left out.
///
/// **What it ranks against.** The calendar only loads a few weeks around the displayed period, and the ranker rebuilds the
/// fitness series from the activities it is given, so a short history would under-count chronic load and make the form
/// look worse than it is. The view model therefore reads its own inputs from the stores when it ranks:
/// ``historyDays`` days of activities, and the active plan, the races and the workouts around the day.
///
/// **The target.** Replacing, the ranker aims at the load of the workout that goes. Adding, it aims at the time the
/// micro-cycle has left, for which it needs the micro-cycle's planned volume. The app doesn't keep a volume per
/// micro-cycle, so ``MicroTimes`` takes the median planned time of the plan's other micro-cycles with the same
/// phase and role. Without one, or when the day's micro-cycle already has that much planned, the ranker has no target
/// and ranks every variant, which takes longer (``isUntargeted``).
@Observable
@MainActor
public final class WorkoutSuggestionsViewModel {
    /// One workout in the list.
    public struct Row: Identifiable, Equatable, Sendable {
        public var id: UUID { ranked.id }
        /// The workout's title, as the planned-workout sheet would name it ("40min Easy Run"), so variants of one template
        /// tell apart.
        public let title: String
        /// Its size: duration and load.
        public let detail: String
        /// What it does to the plan: the form at the end of the micro-cycle and the micro-cycle's planned time.
        public let effects: [String]
        /// Why it ranks lower, most telling first; empty when nothing counts against it.
        public let reasons: [String]
        /// The ranked workout, handed to the caller when the row is picked.
        public let ranked: RankedWorkout
    }

    /// The planned times of the micro-cycle holding a day, in seconds.
    struct MicroTimes: Equatable, Sendable {
        /// The median planned time of the plan's other micro-cycles with the same phase and role; `nil` when there is
        /// none or none holds a workout.
        var typical: TimeInterval?
        /// What the day's own micro-cycle has planned now.
        var planned: TimeInterval

        /// The time left in the micro-cycle against ``typical``; `nil` without a typical time.
        var remaining: TimeInterval? { typical.map { $0 - planned } }
    }

    /// Where the ranking is.
    public enum Phase: Equatable, Sendable {
        case idle
        case ranking
        case ranked
        case failed(String)

        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    /// How many days of activities the ranking reads before the day, so chronic load (42 days) is complete.
    static let historyDays = 180
    /// How many days after the day the plan and the races are read.
    static let horizonDays = 120

    private let model: TrainingModel
    private let ranking: @Sendable (WorkoutRankingInput) async throws -> [RankedWorkout]
    private let now: @MainActor () -> Date

    /// The day the workout is for.
    public let day: Date
    /// The planned workout being replaced, or `nil` when adding.
    public let replacing: PlannedActivity?
    /// The name of the workout being replaced, for the sheet's title.
    public let replacedName: String?
    /// The state of the ranking.
    public private(set) var phase: Phase = .idle
    /// Every ranked workout, best first.
    public private(set) var rows: [Row] = []
    /// The micro-cycle's typical planned time the ranking aimed at, in seconds; `nil` when it had none.
    public private(set) var microTarget: TimeInterval?
    /// The time left in the day's micro-cycle against ``microTarget``; `nil` without a target.
    public private(set) var microRemaining: TimeInterval?
    /// How distances are written in a workout's title; defaults to the device's measurement system.
    public var distanceSystem: DistanceSystem = Locale.current.measurementSystem == .metric ? .metric : .imperial
    /// The text in the search bar.
    public var searchText = ""

    /// The rows whose title contains the search text, case and diacritics aside; all of them for an empty search.
    public var filteredRows: [Row] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.title.localizedStandardContains(query) }
    }

    /// Whether the ranking has no target, so it ranks every variant and takes longer: adding with no typical micro-cycle to
    /// compare with, or to a micro-cycle that already has its typical time planned.
    public var isUntargeted: Bool {
        guard replacing == nil else { return false }
        guard let microRemaining else { return true }
        return microRemaining <= 0
    }

    /// What the sheet says while it ranks.
    public var rankingMessage: String {
        guard isUntargeted else { return "Ranking the workouts" }
        return microTarget == nil
            ? "Ranking every workout. This can take a while."
            : "This micro-cycle already has its usual time planned, so every workout is ranked. This can take a while."
    }

    /// Creates the view model.
    ///
    /// - Parameters:
    ///   - model: The training model whose stores, athlete and templates are ranked against.
    ///   - day: The day the workout is for.
    ///   - replacing: The planned workout that goes, if any.
    ///   - ranking: Does the ranking; TrainingKit's ranker by default, replaced by tests.
    ///   - now: The current time; replaced by tests.
    init(
        model: TrainingModel, day: Date, replacing: PlannedActivity? = nil,
        ranking: @escaping @Sendable (WorkoutRankingInput) async throws -> [RankedWorkout] = { try await $0.rank() },
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.model = model
        self.day = day
        self.replacing = replacing
        self.replacedName = replacing.flatMap { plan in model.workouts.first { $0.id == plan.workoutID }?.name }
        self.ranking = ranking
        self.now = now
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.athlete.timeZone
        return calendar
    }

    /// The cycles of the active plan within a year of `day`, from the store: the calendar's model holds only the cycles
    /// of the weeks it has loaded, and the other micro-cycles of the plan are what the typical time is taken from.
    private func activeCycles(around day: Date) async throws -> [TrainingCycle] {
        let calendar = calendar
        let from = calendar.date(byAdding: .day, value: -366, to: day) ?? day
        let to = calendar.date(byAdding: .day, value: 366, to: day) ?? day
        return try await model.stores.activeCycles(in: from...to)
    }

    /// The planned times of the micro-cycle holding `date`: what it has now and the median of the plan's other
    /// micro-cycles with the same phase and load role. Read from the store for the whole date range of each micro-cycle,
    /// not from the model's loaded window, which holds only part of a micro-cycle outside it.
    ///
    /// - Parameter date: A day in the micro-cycle.
    /// - Returns: `nil` when no micro-cycle holds the day.
    /// - Throws: Whatever the stores throw.
    func microTimes(on date: Date) async throws -> MicroTimes? {
        let calendar = calendar
        let day = calendar.startOfDay(for: date)
        func range(_ cycle: TrainingCycle) -> ClosedRange<Date> {
            calendar.startOfDay(for: cycle.dateRange.lowerBound)...calendar.startOfDay(for: cycle.dateRange.upperBound)
        }
        let micros = try await activeCycles(around: day).filter { $0.level == .micro }
        guard let micro = micros.first(where: { range($0).contains(day) }) else { return nil }
        let peers = micros.filter { $0.id != micro.id && $0.phase == micro.phase && $0.loadRole == micro.loadRole }
        let involved = [micro] + peers
        let lower = involved.map { range($0).lowerBound }.min() ?? day
        let upper = involved.map { range($0).upperBound }.max() ?? day
        let planned = try await model.stores.activePlannedActivities(in: lower...upper)
        let workoutsByID = Dictionary(
            try await model.stores.workoutStore.workouts().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let estimator = WorkoutDurationEstimator()
        let athlete = model.athlete
        func seconds(in cycle: TrainingCycle) -> TimeInterval {
            let span = range(cycle)
            return planned.filter { span.contains(calendar.startOfDay(for: $0.date)) }.reduce(0) { total, plan in
                total + (workoutsByID[plan.workoutID].map { estimator.duration(for: $0, athlete: athlete) } ?? 0)
            }
        }
        let values = peers.map(seconds(in:)).filter { $0 > 0 }.sorted()
        var typical: TimeInterval?
        if !values.isEmpty {
            let middle = values.count / 2
            typical = values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
        }
        return MicroTimes(typical: typical, planned: seconds(in: micro))
    }

    /// Ranks the workouts for the day. A second call while one runs, or after one has finished, does nothing; cancelling the
    /// calling task (the sheet closing) stops the ranking.
    public func load() async {
        guard phase == .idle || phase.isFailure else { return }
        phase = .ranking
        // The deciding state is read before the first `await`.
        let day = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: now())
        let replacing = replacing
        let athlete = model.athlete
        let templates = model.libraryTemplates
        let distanceSystem = distanceSystem
        let ranking = ranking
        let stores = model.stores
        let calendar = calendar
        do {
            let cycles = try await activeCycles(around: day)
            let times = try await microTimes(on: day)
            microTarget = times?.typical
            microRemaining = times?.remaining
            let from = calendar.date(byAdding: .day, value: -Self.historyDays, to: day) ?? day
            let to = calendar.date(byAdding: .day, value: Self.horizonDays, to: day) ?? day
            let activities = try await stores.activityStore.activities(in: from...max(from, min(day, today)).addingTimeInterval(86_399))
            let plan = try await stores.activePlannedActivities(in: from...to)
            let races = try await stores.raceStore.races(in: from...to)
            let workouts = try await stores.workoutStore.workouts()
            let target = microTarget
            let input = WorkoutRankingInput(
                day: day, replacing: replacing, plan: plan, workouts: workouts, templates: templates, cycles: cycles,
                activities: activities, races: races, athlete: athlete, microSeconds: target, today: today
            )
            let work = Task.detached(priority: .userInitiated) {
                try await ranking(input).map { Self.row(for: $0, microTarget: target, distanceSystem: distanceSystem) }
            }
            rows = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            phase = .ranked
        } catch is CancellationError {
            phase = .idle
        } catch {
            rows = []
            phase = .failed("Couldn't rank the workouts: \(error.localizedDescription)")
        }
    }

    // MARK: Text

    private nonisolated static func row(for ranked: RankedWorkout, microTarget: TimeInterval?, distanceSystem: DistanceSystem) -> Row {
        var effects: [String] = []
        if let tsb = ranked.endOfMicroTSB {
            effects.append("Form at the end of the micro-cycle: \(Int(tsb.rounded()))")
        }
        if let planned = ranked.microSeconds {
            effects.append(microTarget.map { "Micro-cycle time: \(duration(planned)) of about \(duration($0))" }
                ?? "Micro-cycle time: \(duration(planned))")
        }
        return Row(
            title: ranked.template.defaultTitle(values: ranked.values, distanceSystem: distanceSystem),
            detail: "\(duration(ranked.seconds)) · load \(Int(ranked.load.rounded()))",
            effects: effects, reasons: ranked.reasons.map(reason(for:)), ranked: ranked
        )
    }

    private nonisolated static func reason(for reason: WorkoutRankReason) -> String {
        switch reason {
        case .addsRisk(let rule, let day):
            "Adds a \(rule.displayName.lowercased()) risk from \(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))."
        case .recoveryDaysShort(let needed, let available):
            "Wants \(needed) day\(needed == 1 ? "" : "s") free around it; \(available) left."
        case .notAskedInPhase(let phase):
            "A \(phase.displayName.lowercased()) micro-cycle doesn't ask for this kind of session."
        case .aboveMicroVolume(let by):
            "\(duration(by)) over the micro-cycle's planned time."
        }
    }

    /// "45 min", "1 h 20 min", "1 h".
    nonisolated static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(max(minutes, 0)) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
