import Foundation
import TrainingCore

/// One step of a planned workout as the watch runs it: the workout's blocks laid out in order,
/// each repetition of a repeated block its own step (WATCH-104).
public struct PlannedStep: Sendable, Hashable, Identifiable {
    /// Where the step is in the whole workout, from 0.
    public let index: Int
    /// The step itself: its kind, goal and targets, as TrainingKit has them.
    public let step: WorkoutStep
    /// The block the step comes from, from 0.
    public let blockIndex: Int
    /// Which repetition of its block this is, from 1.
    public let repetition: Int
    /// How many times its block repeats.
    public let repetitions: Int

    public var id: Int { index }
}

/// How far into the current step the run is.
public struct StepProgress: Sendable, Hashable {
    /// Time left in a step with a time goal.
    public let remainingTime: TimeInterval?
    /// Distance left, in metres, in a step with a distance goal.
    public let remainingDistance: Double?
    /// How much of the step is done, 0 to 1, when its goal is time or distance; `nil` for an open step.
    public let fraction: Double?
}

/// Moves through a planned workout's steps as the run goes (WATCH-104): a step with a time or
/// distance goal ends when it is reached, an open step waits for the lap button, and the lap button
/// ends any step early.
///
/// Pure logic with no clock of its own. The watch tells it how much workout time (paused time left
/// out) and distance there has been, and it says which steps ended and which began, so it can be
/// tested without a run. After the last step ``isFinished`` is `true`; the run goes on as a free
/// run, which isn't this type's business.
public struct WorkoutStepEngine: Sendable {
    /// How a step came to end.
    public enum Reason: Sendable, Hashable {
        /// Its time or distance was reached.
        case goalReached
        /// The lap button ended it.
        case lap
    }

    /// One step ending and the next beginning.
    public struct Transition: Sendable, Hashable {
        /// The step that ended.
        public let ended: PlannedStep
        /// The step that began; `nil` when the workout's last step ended.
        public let started: PlannedStep?
        /// Why `ended` ended.
        public let reason: Reason
        /// The workout time, paused time left out, at which `ended` ended: its goal's boundary for a
        /// goal reached, or the moment of the lap. Lets the caller date the step's end exactly rather
        /// than when it noticed.
        public let endedAt: TimeInterval
    }

    /// Every step of the workout, in order.
    public let steps: [PlannedStep]

    /// The step being run, or `nil` once every step is done (or the workout has none).
    public var current: PlannedStep? { currentIndex.map { steps[$0] } }

    /// The step after the current one, or `nil` when the current one is the last.
    public var next: PlannedStep? {
        guard let currentIndex, currentIndex + 1 < steps.count else { return nil }
        return steps[currentIndex + 1]
    }

    /// The workout time since the current step began, or `nil` once the steps are done.
    public func stepElapsed(at elapsed: TimeInterval) -> TimeInterval? {
        isFinished ? nil : max(elapsed - stepStartElapsed, 0)
    }

    /// The metres run since the current step began, or `nil` once the steps are done.
    public func stepDistance(at distance: Double) -> Double? {
        isFinished ? nil : max(distance - stepStartDistance, 0)
    }

    /// Whether every step is done, or there were none.
    public var isFinished: Bool { currentIndex == nil }

    private var currentIndex: Int?
    private var stepStartElapsed: TimeInterval
    private var stepStartDistance: Double

    /// Lays out `blocks` and starts at their first step.
    ///
    /// - Parameters:
    ///   - blocks: The workout's blocks.
    ///   - elapsed: The workout time when the first step starts; 0 for a run that has just begun.
    ///   - distance: The distance, in metres, when the first step starts.
    public init(blocks: [WorkoutBlock], elapsed: TimeInterval = 0, distance: Double = 0) {
        var steps: [PlannedStep] = []
        for (blockIndex, block) in blocks.enumerated() {
            let repetitions = max(block.repetitions, 1)
            for repetition in 1...repetitions {
                for step in block.steps {
                    steps.append(PlannedStep(
                        index: steps.count, step: step, blockIndex: blockIndex,
                        repetition: repetition, repetitions: repetitions))
                }
            }
        }
        self.steps = steps
        currentIndex = steps.isEmpty ? nil : 0
        stepStartElapsed = elapsed
        stepStartDistance = distance
    }

    /// Ends every step whose goal has been reached by now, one transition each: a long gap (the
    /// app was suspended) can pass several short steps at once.
    ///
    /// Each next step starts where the last one's goal ended, not at `elapsed`, so time goals don't
    /// drift by the update interval.
    ///
    /// - Parameters:
    ///   - elapsed: Workout time so far, with paused time left out.
    ///   - distance: Distance so far, in metres.
    /// - Returns: The steps that ended, earliest first; empty when none did.
    public mutating func update(elapsed: TimeInterval, distance: Double) -> [Transition] {
        var transitions: [Transition] = []
        while let index = currentIndex {
            let step = steps[index]
            switch step.step.goal {
            case .time(let seconds) where elapsed - stepStartElapsed >= seconds:
                transitions.append(advance(reason: .goalReached, elapsed: stepStartElapsed + seconds, distance: distance))
            case .distance(let metres) where distance - stepStartDistance >= metres:
                transitions.append(advance(reason: .goalReached, elapsed: elapsed, distance: stepStartDistance + metres))
            default:
                return transitions
            }
        }
        return transitions
    }

    /// Ends the current step now, whatever its goal: the lap button.
    ///
    /// - Returns: The step that ended and the one that began; `nil` when every step is already done.
    public mutating func lap(elapsed: TimeInterval, distance: Double) -> Transition? {
        guard currentIndex != nil else { return nil }
        return advance(reason: .lap, elapsed: elapsed, distance: distance)
    }

    /// How far into the current step the run is, or `nil` when every step is done.
    public func progress(elapsed: TimeInterval, distance: Double) -> StepProgress? {
        guard let current else { return nil }
        switch current.step.goal {
        case .time(let seconds):
            let done = max(elapsed - stepStartElapsed, 0)
            return StepProgress(
                remainingTime: max(seconds - done, 0), remainingDistance: nil,
                fraction: seconds > 0 ? min(done / seconds, 1) : 1)
        case .distance(let metres):
            let done = max(distance - stepStartDistance, 0)
            return StepProgress(
                remainingTime: nil, remainingDistance: max(metres - done, 0),
                fraction: metres > 0 ? min(done / metres, 1) : 1)
        case .open:
            return StepProgress(remainingTime: nil, remainingDistance: nil, fraction: nil)
        }
    }

    private mutating func advance(reason: Reason, elapsed: TimeInterval, distance: Double) -> Transition {
        let index = currentIndex!
        let ended = steps[index]
        let startedIndex = index + 1 < steps.count ? index + 1 : nil
        currentIndex = startedIndex
        stepStartElapsed = elapsed
        stepStartDistance = distance
        return Transition(ended: ended, started: startedIndex.map { steps[$0] }, reason: reason, endedAt: elapsed)
    }
}
