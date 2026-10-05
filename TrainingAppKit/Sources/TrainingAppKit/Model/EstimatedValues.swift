import Foundation
import TrainingCore

// Which of the numbers the app shows are estimates (MVP2-8). Only estimates are marked, with a
// "~"; measured values and the targets a plan sets are shown plainly.

extension LoadMethod {
    /// Whether a load computed this way is an estimate: one from a planned workout, or from
    /// perceived effort instead of heart rate. Heart-rate TRIMP is measured, and a load the athlete
    /// entered is their own figure, so neither is.
    var isEstimate: Bool {
        switch self {
        case .exponentialTRIMP, .manual: false
        case .estimatedFromPlan, .durationRPE: true
        }
    }
}

extension PlannedActivity {
    /// Whether the plan's expected load is an estimate: `false` when the athlete set it with
    /// ``PlannedActivity/expectedLoadOverride``, which makes it a target like a step's duration.
    var isExpectedLoadEstimated: Bool {
        expectedLoadOverride == nil
    }
}

extension StructuredWorkout {
    /// Whether the workout's expected duration is forecast from the athlete's paces rather than set
    /// by its steps: it has a distance or open step, whose time depends on how fast the athlete goes.
    /// A workout of time steps alone has a target duration. Blocks repeated zero times don't count.
    var isDurationForecast: Bool {
        countedSteps.contains { step in
            switch step.goal {
            case .time: false
            case .distance, .open: true
            }
        }
    }

    /// Whether the workout's expected distance is forecast from the athlete's paces rather than set
    /// by its steps: only a workout made solely of distance steps has a target distance. Blocks
    /// repeated zero times don't count.
    var isDistanceForecast: Bool {
        let steps = countedSteps
        let distanceOnly = !steps.isEmpty && steps.allSatisfy { step in
            if case .distance = step.goal { return true }
            return false
        }
        return !distanceOnly
    }

    /// The steps of every block that's actually performed.
    private var countedSteps: [WorkoutStep] {
        blocks.filter { $0.repetitions > 0 }.flatMap(\.steps)
    }
}

extension FitnessMetrics {
    /// Whether Form (TSB) on `day` is an estimate (MVP2-8). TSB is the previous day's CTL minus its
    /// ATL, so it's projected when the previous day's metrics are, not when `day`'s are: today's Form
    /// is known even before today's workout is done. `false` when the previous day isn't in `series`.
    ///
    /// - Parameters:
    ///   - day: The day whose Form is shown.
    ///   - series: The loaded metrics to look the previous day up in.
    ///   - calendar: The athlete's calendar, for finding the previous day.
    static func isFormProjected(on day: Date, in series: [FitnessMetrics], calendar: Calendar) -> Bool {
        guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return false }
        return series.first { calendar.isDate($0.day, inSameDayAs: previous) }?.isProjected ?? false
    }
}
