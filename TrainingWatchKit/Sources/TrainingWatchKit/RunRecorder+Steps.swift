import Foundation
import TrainingCore

/// Running a planned workout's steps (WATCH-104): the `WorkoutStepEngine` decides when a step ends,
/// this writes what happened into the saved workout and has the backend tap the wrist.
extension RunRecorder {
    /// Starts the steps of `plan`: tags the workout with the planned activity's ID, so TrainingApp
    /// can match the run to its plan exactly, and starts watching the clock and the distance.
    ///
    /// - Parameters:
    ///   - plan: The planned workout being run.
    ///   - start: When the run started, which is when its first step does.
    func beginSteps(for plan: WatchPlannedWorkout, at start: Date) async {
        stepEngine = WorkoutStepEngine(blocks: plan.blocks)
        announcedAheadIndex = nil
        lastCountdownSecond = nil
        stepStartDate = start
        alertStepStarted()
        do {
            try await builder?.addMetadata(WorkoutMetadata.workout(plannedActivityID: plan.id, name: plan.name))
        } catch {
            log.error("workout tag not written: \(error.localizedDescription, privacy: .public)")
        }
        stepTicker?.cancel()
        // A fifth of a second keeps the countdown tones on their seconds and is cheap enough to leave running.
        stepTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                await self?.tickSteps()
            }
        }
    }

    /// Ends the steps whose time or distance has been reached.
    func tickSteps() async {
        guard phase == .running, var engine = stepEngine, !engine.isFinished else { return }
        let transitions = engine.update(elapsed: elapsed(), distance: distanceMeters)
        guard !transitions.isEmpty else {
            announceNextAhead(engine)
            countDown(engine)
            return
        }
        stepEngine = engine
        await record(transitions)
    }

    /// Says the next step before it starts when it is a work step and the current one is nearly over
    /// (WATCH-107), once per step.
    private func announceNextAhead(_ engine: WorkoutStepEngine) {
        guard let next = engine.next, announcedAheadIndex != next.index,
              StepAnnouncement.announcesAhead(
                next: next, progress: engine.progress(elapsed: elapsed(), distance: distanceMeters),
                settings: backend.cueSettings)
        else { return }
        announcedAheadIndex = next.index
        backend.play(.stepAnnouncement(StepAnnouncement.text(for: next, ahead: true)))
    }

    /// The last five seconds of a step with a time goal and a step after it: a short tone each second
    /// (WATCH-107), then the next step's longer tone as it starts. The tick for a second is sounded
    /// once, on the first tick of the clock that sees it.
    private func countDown(_ engine: WorkoutStepEngine) {
        guard engine.next != nil,
              let remaining = engine.progress(elapsed: elapsed(), distance: distanceMeters)?.remainingTime
        else { return }
        let second = Int(remaining.rounded(.up))
        guard (1...5).contains(second), lastCountdownSecond != second else { return }
        lastCountdownSecond = second
        backend.play(.countdownTick)
    }

    /// The lap button. During a planned workout it ends the current step and moves on, marked as a
    /// lap; in a free run, or after the last step, it only marks a lap.
    public func lap() async {
        guard phase == .running else { return }
        if var engine = stepEngine, !engine.isFinished {
            // A second tap, or a brush of the wrist, right after a step began would skip that one too.
            guard Date.now.timeIntervalSince(stepStartDate) > 1,
                  let transition = engine.lap(elapsed: elapsed(), distance: distanceMeters) else { return }
            stepEngine = engine
            await record([transition])
        } else {
            backend.play(.lapMarked)
            await addEvents([RunEvent(kind: .lap, start: .now, end: .now, metadata: nil)])
        }
    }

    /// How far into the current step the run is, or `nil` in a free run and after the last step.
    ///
    /// - Parameter date: When to measure at, so a ticking view stays in step with the clock.
    public func stepProgress(at date: Date = .now) -> StepProgress? {
        stepEngine?.progress(elapsed: elapsed(at: date), distance: distanceMeters)
    }

    /// Writes a segment event for each step that ended, and a lap event for one the lap button
    /// ended, then taps the wrist once for the change.
    private func record(_ transitions: [WorkoutStepEngine.Transition]) async {
        var events: [RunEvent] = []
        let now = Date.now
        let elapsedNow = elapsed(at: now)
        for transition in transitions {
            // Dated by the boundary the engine computed, not by when the tick noticed it, so a step
            // of 6 s is 6 s and steps passed in one gap don't all end "now". (A pause inside the gap
            // before the tick would shift this by at most that gap.) Pauses inside a step are part
            // of its interval, since it is dated on the wall clock.
            let end = min(now.addingTimeInterval(transition.endedAt - elapsedNow), now)
            events.append(segmentEvent(
                for: transition.ended, from: stepStartDate, to: end, end: WorkoutMetadata.StepEnd(transition.reason)))
            if transition.reason == .lap {
                events.append(RunEvent(kind: .lap, start: end, end: end, metadata: nil))
            }
            stepStartDate = max(end, stepStartDate)
            // A different tap when the workout's last step is over.
            if transition.started == nil {
                backend.cancelPendingCues()
                backend.play(.goalReached)
            }
        }
        // The new step's own haptic comes with its alert state (WATCH-106), once, for the last step
        // started when several went by in one gap.
        if transitions.last?.started != nil {
            alertStepStarted()
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
    ) -> RunEvent {
        RunEvent(
            kind: .segment, start: start, end: max(end, start),
            metadata: WorkoutMetadata.segment(for: step, end: reason))
    }

    /// Writes events to the workout. Ones that fail are kept and tried again with the next batch
    /// and when the run is saved (`flushPendingEvents()`), so a hiccup doesn't lose a step.
    private func addEvents(_ events: [RunEvent]) async {
        let batch = pendingEvents + events
        guard !batch.isEmpty, let builder else { return }
        pendingEvents = []
        do {
            try await builder.addEvents(batch)
            eventsWritten += batch.count
        } catch {
            pendingEvents = batch
            log.error("workout events not written, will retry: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Tries once more to write events that failed earlier, before the workout is ended.
    func flushPendingEvents() async {
        await addEvents([])
    }
}
