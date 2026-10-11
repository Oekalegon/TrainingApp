import Foundation
#if canImport(HealthKit)
import HealthKit
#if canImport(WorkoutKit)
import WorkoutKit
#endif

/// ``WorkoutInspecting`` on a real `HKHealthStore` (MVP2-146 spike): reads each recent workout's
/// events, sub-activities, metadata and the plan it was started from.
@MainActor
struct HealthKitWorkoutInspector: WorkoutInspecting {
    let healthStore: HKHealthStore

    func inspectRecentWorkouts(limit: Int) async throws -> String {
        // A workout activity's distance and speed summaries are only readable once the athlete has
        // allowed those types, which the app doesn't otherwise ask for yet (MVP2-146). Read-only;
        // HealthKit shows its sheet once, and not again for types already answered.
        try await healthStore.requestAuthorization(toShare: [], read: [
            HKQuantityType(.distanceWalkingRunning), HKQuantityType(.runningSpeed), HKQuantityType(.heartRate),
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout()],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: limit
        )
        let workouts = try await descriptor.result(for: healthStore)
        var inspected: [InspectedWorkout] = []
        for workout in workouts {
            inspected.append(await Self.inspect(workout))
        }
        return WorkoutInspectionReport.format(inspected, generatedAt: .now)
    }

    private static func inspect(_ workout: HKWorkout) async -> InspectedWorkout {
        var planID: UUID?
        var planSummary: String?
        #if canImport(WorkoutKit)
        if let plan = try? await workout.workoutPlan {
            planID = plan.id
            planSummary = summary(of: plan)
        }
        #endif
        return InspectedWorkout(
            id: workout.uuid,
            activityType: name(of: workout.workoutActivityType),
            start: workout.startDate,
            end: workout.endDate,
            planID: planID,
            planSummary: planSummary,
            events: (workout.workoutEvents ?? []).map(event),
            activities: workout.workoutActivities.map { activity in
                InspectedWorkout.Activity(
                    activityType: name(of: activity.workoutConfiguration.activityType),
                    start: activity.startDate,
                    end: activity.endDate,
                    events: activity.workoutEvents.map(event),
                    metadata: strings(activity.metadata),
                    statistics: statistics(activity)
                )
            },
            metadata: strings(workout.metadata)
        )
    }

    private static func event(_ event: HKWorkoutEvent) -> InspectedWorkout.Event {
        InspectedWorkout.Event(
            type: name(of: event.type), start: event.dateInterval.start, end: event.dateInterval.end,
            metadata: strings(event.metadata)
        )
    }

    /// Every quantity HealthKit summarised for `activity`, as "sum 10.2 km, avg 150 count/min".
    private static func statistics(_ activity: HKWorkoutActivity) -> [String: String] {
        var result: [String: String] = [:]
        for (type, statistics) in activity.allStatistics {
            var parts: [String] = []
            if let sum = statistics.sumQuantity() { parts.append("sum \(sum)") }
            if let average = statistics.averageQuantity() { parts.append("avg \(average)") }
            if let minimum = statistics.minimumQuantity() { parts.append("min \(minimum)") }
            if let maximum = statistics.maximumQuantity() { parts.append("max \(maximum)") }
            result[type.identifier.replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "")] = parts.joined(separator: ", ")
        }
        return result
    }

    private static func strings(_ metadata: [String: Any]?) -> [String: String] {
        (metadata ?? [:]).mapValues { "\($0)" }
    }

    private static func name(of type: HKWorkoutActivityType) -> String {
        "activityType(\(type.rawValue))"
    }

    private static func name(of type: HKWorkoutEventType) -> String {
        switch type {
        case .pause: "pause"
        case .resume: "resume"
        case .lap: "lap"
        case .marker: "marker"
        case .motionPaused: "motionPaused"
        case .motionResumed: "motionResumed"
        case .segment: "segment"
        case .pauseOrResumeRequest: "pauseOrResumeRequest"
        @unknown default: "eventType(\(type.rawValue))"
        }
    }

    #if canImport(WorkoutKit)
    private static func summary(of plan: WorkoutPlan) -> String {
        switch plan.workout {
        case .custom(let custom):
            let steps = custom.blocks.reduce(0) { $0 + $1.steps.count }
            return "custom workout '\(custom.displayName ?? "")', warm-up \(custom.warmup == nil ? "no" : "yes"), "
                + "\(custom.blocks.count) blocks (\(steps) steps), cool-down \(custom.cooldown == nil ? "no" : "yes")"
        case .goal: return "goal workout"
        case .pacer: return "pacer workout"
        case .swimBikeRun: return "swim-bike-run workout"
        @unknown default: return "other workout"
        }
    }
    #endif
}
#endif
