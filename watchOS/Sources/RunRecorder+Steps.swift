import HealthKit
import TrainingCore
import TrainingWatchKit
import WatchKit

/// Running a planned workout's steps (WATCH-104): the `WorkoutStepEngine` decides when a step ends,
/// this writes what happened into the saved workout and taps the wrist.
extension RunRecorder {
    /// Starts the steps of `plan`: tags the workout with the planned activity's ID, so TrainingApp
    /// can match the run to its plan exactly, and starts watching the clock and the distance.
    ///
    /// - Parameters:
    ///   - plan: The planned workout being run.
    ///   - start: When the run started, which is when its first step does.
    func beginSteps(for plan: WatchPlannedWorkout, at start: Date) async {
        stepEngine = WorkoutStepEngine(blocks: plan.blocks)
        stepStartDate = start
        do {
            try await builder?.addMetadata(WorkoutMetadata.workout(plannedActivityID: plan.id, name: plan.name))
        } catch {
            log.error("workout tag not written: \(error.localizedDescription, privacy: .public)")
        }
        stepTicker?.cancel()
        // Half a second is fine enough for a step to end on time and cheap enough to leave running.
        stepTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                await self?.tickSteps()
            }
        }
    }

    /// Ends the steps whose time or distance has been reached.
    private func tickSteps() async {
        guard phase == .running, var engine = stepEngine, !engine.isFinished else { return }
        let transitions = engine.update(elapsed: elapsed(), distance: distanceMeters)
        guard !transitions.isEmpty else { return }
        stepEngine = engine
        await record(transitions)
    }

    /// The lap button. During a planned workout it ends the current step and moves on, marked as a
    /// lap; in a free run, or after the last step, it only marks a lap.
    func lap() async {
        guard phase == .running else { return }
        if var engine = stepEngine, !engine.isFinished,
           let transition = engine.lap(elapsed: elapsed(), distance: distanceMeters) {
            stepEngine = engine
            await record([transition])
        } else {
            WKInterfaceDevice.current().play(.click)
            await addEvents([HKWorkoutEvent(type: .lap, dateInterval: DateInterval(start: .now, duration: 0), metadata: nil)])
        }
    }

    /// How far into the current step the run is, or `nil` in a free run and after the last step.
    ///
    /// - Parameter date: When to measure at, so a ticking view stays in step with the clock.
    func stepProgress(at date: Date = .now) -> StepProgress? {
        stepEngine?.progress(elapsed: elapsed(at: date), distance: distanceMeters)
    }

    /// Writes a segment event for each step that ended, and a lap event for one the lap button
    /// ended, then taps the wrist once for the change.
    private func record(_ transitions: [WorkoutStepEngine.Transition]) async {
        var events: [HKWorkoutEvent] = []
        for transition in transitions {
            let now = Date.now
            events.append(segmentEvent(
                for: transition.ended, from: stepStartDate, to: now, end: WorkoutMetadata.StepEnd(transition.reason)))
            if transition.reason == .lap {
                events.append(HKWorkoutEvent(type: .lap, dateInterval: DateInterval(start: now, duration: 0), metadata: nil))
            }
            stepStartDate = now
            // A different tap when the workout's last step is over.
            WKInterfaceDevice.current().play(transition.started == nil ? .success : .notification)
        }
        await addEvents(events)
    }

    /// When the run ends in the middle of a step, writes that step's segment too, so its time is
    /// in the saved workout.
    func closeCurrentStep() async {
        guard let current = stepEngine?.current else { return }
        // Forgotten once written, so a save that is tried again doesn't write it twice.
        stepEngine = nil
        await addEvents([segmentEvent(for: current, from: stepStartDate, to: .now, end: .workoutEnded)])
    }

    private func segmentEvent(
        for step: PlannedStep, from start: Date, to end: Date, end reason: WorkoutMetadata.StepEnd
    ) -> HKWorkoutEvent {
        HKWorkoutEvent(
            type: .segment, dateInterval: DateInterval(start: start, end: max(end, start)),
            metadata: WorkoutMetadata.segment(for: step, end: reason))
    }

    private func addEvents(_ events: [HKWorkoutEvent]) async {
        guard !events.isEmpty, let builder else { return }
        do {
            try await builder.addWorkoutEvents(events)
            eventsWritten += events.count
        } catch {
            log.error("workout events not written: \(error.localizedDescription, privacy: .public)")
        }
    }
}
