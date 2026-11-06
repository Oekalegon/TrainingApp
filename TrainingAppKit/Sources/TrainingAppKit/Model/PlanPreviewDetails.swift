import Foundation
import TrainingCore

/// What the Create Plan wizard shows of a generated plan beyond the summary (MVP5-121): the micro-cycles with their
/// workouts, the projected form, and what activating the plan would replace.
///
/// It is made from a ``PlanPreview`` (TrainingKit reads the active plan's upcoming workouts for it) and the workout
/// library, which names the workouts of the plan being replaced; the proposal's own workouts are in the preview. A
/// plain value, so the screen holds no logic and tests read it directly.
public struct PlanPreviewDetails: Equatable, Sendable {
    /// One planned workout, as a line in a list.
    public struct Item: Identifiable, Equatable, Sendable {
        public let id: UUID
        /// The calendar day.
        public let day: Date
        /// The workout's name.
        public let title: String
    }

    /// One micro-cycle of the layout with its workouts.
    public struct Micro: Identifiable, Equatable, Sendable {
        public let id: UUID
        /// "Micro-cycle 3": its position in the plan. TrainingKit's own name repeats the approach on every micro-cycle and says
        /// "Week" even when the micro-cycles have 10 or 14 days, so the list numbers them itself.
        public let name: String
        /// The phase it belongs to, as shown to the athlete.
        public let phase: String
        public let dates: ClosedRange<Date>
        /// Its workouts in date order.
        public let items: [Item]
    }

    /// One day of the projected form.
    public struct FormPoint: Equatable, Sendable {
        public let day: Date
        /// Fitness (chronic training load).
        public let ctl: Double
        /// Form (training stress balance).
        public let tsb: Double
    }

    /// The plan an activation would replace.
    public struct Replacement: Equatable, Sendable {
        public let planName: String
        /// Its upcoming planned workouts that no activity has completed; they stop counting on activation, nothing is deleted.
        public let items: [Item]
        /// Whether the plan has a completed workout: it is then cancelled and kept as history, otherwise it becomes a draft.
        public let isFollowed: Bool
    }

    /// The micro-cycles in date order.
    public let micros: [Micro]
    /// Fitness and form from the plan's first day to its last, with the proposal in them.
    public let form: [FormPoint]
    /// What activating would replace; `nil` when no plan is active.
    public let replacement: Replacement?

    /// The highest fitness the plan reaches, `nil` without a projection.
    public var peakCTL: Double? { form.map(\.ctl).max() }
    /// The fitness on the plan's last day, `nil` without a projection.
    public var finalCTL: Double? { form.last?.ctl }

    /// - Parameters:
    ///   - preview: The preview from ``TrainingModel/preview(_:asOf:)``.
    ///   - library: The workout library, to name the replaced plan's workouts.
    ///   - calendar: The athlete's calendar.
    init(_ preview: PlanPreview, library: [StructuredWorkout], calendar: Calendar) {
        func names(_ workouts: [StructuredWorkout]) -> [UUID: String] {
            Dictionary(workouts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        }
        let proposed = names(preview.workouts)
        let fromLibrary = names(library)
        func item(_ activity: PlannedActivity) -> Item {
            Item(
                id: activity.id, day: calendar.startOfDay(for: activity.date),
                title: proposed[activity.workoutID] ?? fromLibrary[activity.workoutID] ?? "Workout"
            )
        }
        let planned = preview.plannedActivities.map(item).sorted { ($0.day, $0.title) < ($1.day, $1.title) }
        let microCycles = preview.cycles.filter { $0.level == .micro }.sorted { $0.dateRange.lowerBound < $1.dateRange.lowerBound }
        micros = microCycles.enumerated().map { index, cycle in
            let range = calendar.startOfDay(for: cycle.dateRange.lowerBound)...calendar.startOfDay(for: cycle.dateRange.upperBound)
            return Micro(
                id: cycle.id, name: "Micro-cycle \(index + 1)", phase: cycle.phase.displayName, dates: cycle.dateRange,
                items: planned.filter { range.contains($0.day) }
            )
        }
        let first = microCycles.first.map { calendar.startOfDay(for: $0.dateRange.lowerBound) }
        let last = microCycles.last.map { calendar.startOfDay(for: $0.dateRange.upperBound) }
        form = preview.projectedForm.compactMap { metrics in
            guard let first, let last, metrics.day >= first, metrics.day <= last, metrics.ctl.isFinite, metrics.tsb.isFinite else { return nil }
            return FormPoint(day: metrics.day, ctl: metrics.ctl, tsb: metrics.tsb)
        }
        replacement = preview.replacedPlan.map {
            Replacement(
                planName: $0.name, items: preview.replacedActivities.map(item), isFollowed: preview.replacedPlanIsFollowed
            )
        }
    }
}
