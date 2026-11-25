import Foundation
import Testing
import TrainingCore
@testable import TrainingWatchKit

private func time(_ seconds: TimeInterval, kind: StepKind = .work, zone: Int = 2) -> WorkoutStep {
    WorkoutStep(kind: kind, goal: .time(seconds), target: .heartRateZone(zone))
}

private func distance(_ metres: Double, kind: StepKind = .work) -> WorkoutStep {
    WorkoutStep(kind: kind, goal: .distance(metres), target: .heartRateZone(2))
}

private let open = WorkoutStep(kind: .work, goal: .open)

@Suite("WorkoutStepEngine (WATCH-104)")
struct WorkoutStepEngineTests {
    @Test("blocks are laid out in order, each repetition of a repeated block its own step")
    func layout() {
        let engine = WorkoutStepEngine(blocks: [
            WorkoutBlock(steps: [time(600, kind: .warmup)]),
            WorkoutBlock(steps: [time(180), time(120, kind: .recovery)], repetitions: 2),
            WorkoutBlock(steps: [time(300, kind: .cooldown)])
        ])
        #expect(engine.steps.map(\.step.kind) == [.warmup, .work, .recovery, .work, .recovery, .cooldown])
        #expect(engine.steps.map(\.index) == [0, 1, 2, 3, 4, 5])
        #expect(engine.steps.map(\.blockIndex) == [0, 1, 1, 1, 1, 2])
        #expect(engine.steps.map(\.repetition) == [1, 1, 1, 2, 2, 1])
        #expect(engine.steps.map(\.repetitions) == [1, 2, 2, 2, 2, 1])
        #expect(engine.current?.index == 0)
        #expect(engine.next?.index == 1)
        #expect(!engine.isFinished)
    }

    @Test("a workout with no steps is finished from the start")
    func empty() {
        var engine = WorkoutStepEngine(blocks: [])
        #expect(engine.isFinished)
        #expect(engine.current == nil)
        #expect(engine.update(elapsed: 100, distance: 100).isEmpty)
        #expect(engine.lap(elapsed: 100, distance: 100) == nil)
        #expect(engine.progress(elapsed: 0, distance: 0) == nil)
    }

    @Test("a repetition count of 0 or less is run once")
    func nonPositiveRepetitions() {
        let engine = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [time(60)], repetitions: 0)])
        #expect(engine.steps.count == 1)
    }

    @Test("a time step ends when its time is up, and not before")
    func timeGoal() {
        var engine = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [time(60), time(30)])])
        #expect(engine.update(elapsed: 59.9, distance: 0).isEmpty)
        let transitions = engine.update(elapsed: 60.2, distance: 0)
        #expect(transitions.count == 1)
        #expect(transitions.first?.ended.index == 0)
        #expect(transitions.first?.started?.index == 1)
        #expect(transitions.first?.reason == .goalReached)
        #expect(engine.current?.index == 1)
    }

    @Test("the next step starts where the last one's time ended, so late updates don't make time goals drift")
    func noDrift() {
        var engine = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [time(60), time(60)])])
        _ = engine.update(elapsed: 62, distance: 0)
        // The second step began at 60, not 62: it ends at 120.
        #expect(engine.update(elapsed: 119.9, distance: 0).isEmpty)
        #expect(engine.update(elapsed: 120, distance: 0).count == 1)
    }

    @Test("a transition says when its step ended: at the goal's boundary, or at the lap")
    func endedAt() {
        var engine = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [time(60), time(30), time(100)])])
        // Noticed late, after two steps are over: they end at 60 and 90, not at 95.
        let transitions = engine.update(elapsed: 95, distance: 0)
        #expect(transitions.map(\.endedAt) == [60, 90])
        #expect(engine.lap(elapsed: 97, distance: 0)?.endedAt == 97)
    }

    @Test("a distance step ends when its distance is covered, measured from where it began")
    func distanceGoal() {
        var engine = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [time(60), distance(400)])])
        _ = engine.update(elapsed: 60, distance: 150)
        #expect(engine.update(elapsed: 100, distance: 549).isEmpty)
        let transitions = engine.update(elapsed: 110, distance: 550)
        #expect(transitions.first?.ended.index == 1)
        #expect(transitions.first?.reason == .goalReached)
        #expect(engine.isFinished)
    }

    @Test("an open step waits for the lap button however long it takes")
    func openStep() {
        var engine = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [open, time(60)])])
        #expect(engine.update(elapsed: 10_000, distance: 100_000).isEmpty)
        #expect(engine.current?.index == 0)
        let lap = engine.lap(elapsed: 10_000, distance: 100_000)
        #expect(lap?.ended.index == 0)
        #expect(lap?.started?.index == 1)
        #expect(lap?.reason == .lap)
    }

    @Test("the lap button ends a step with a goal early, and the next step starts from that moment")
    func lapEndsEarly() {
        var engine = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [time(600), time(60)])])
        let lap = engine.lap(elapsed: 100, distance: 300)
        #expect(lap?.reason == .lap)
        #expect(engine.current?.index == 1)
        #expect(engine.update(elapsed: 159, distance: 300).isEmpty)
        #expect(engine.update(elapsed: 160, distance: 300).count == 1)
    }

    @Test("ending the last step finishes the workout, and nothing more happens after that")
    func finishing() {
        var engine = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [time(60)])])
        let transitions = engine.update(elapsed: 60, distance: 0)
        #expect(transitions.first?.started == nil)
        #expect(engine.isFinished)
        #expect(engine.next == nil)
        #expect(engine.update(elapsed: 500, distance: 500).isEmpty)
        #expect(engine.lap(elapsed: 500, distance: 500) == nil)
    }

    @Test("lapping the last step finishes the workout")
    func lapFinishes() {
        var engine = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [open])])
        let lap = engine.lap(elapsed: 30, distance: 10)
        #expect(lap?.started == nil)
        #expect(engine.isFinished)
    }

    @Test("a long gap passes several steps at once, earliest first, each ending where its goal did")
    func longGap() {
        var engine = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [time(30), time(30), time(30), time(30)])])
        let transitions = engine.update(elapsed: 100, distance: 0)
        #expect(transitions.map(\.ended.index) == [0, 1, 2])
        #expect(engine.current?.index == 3)
        // The fourth step began at 90, so 10 s of it are done.
        #expect(engine.progress(elapsed: 100, distance: 0)?.remainingTime == 20)
    }

    @Test("a step with a goal of zero ends at once")
    func zeroGoal() {
        var engine = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [time(0), time(60)])])
        #expect(engine.update(elapsed: 0, distance: 0).count == 1)
        #expect(engine.current?.index == 1)
    }

    @Test("progress says what is left and how much is done")
    func progress() {
        var engine = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [time(100), distance(500), open])])
        #expect(engine.progress(elapsed: 25, distance: 0) == StepProgress(remainingTime: 75, remainingDistance: nil, fraction: 0.25))
        _ = engine.update(elapsed: 100, distance: 40)
        #expect(engine.progress(elapsed: 150, distance: 290) == StepProgress(remainingTime: nil, remainingDistance: 250, fraction: 0.5))
        _ = engine.update(elapsed: 200, distance: 540)
        #expect(engine.progress(elapsed: 210, distance: 600) == StepProgress(remainingTime: nil, remainingDistance: nil, fraction: nil))
        _ = engine.lap(elapsed: 220, distance: 650)
        #expect(engine.progress(elapsed: 230, distance: 700) == nil)
    }

    @Test("progress never goes below zero left or above done, even before the step started")
    func progressBounds() {
        let engine = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [time(60)])], elapsed: 50)
        #expect(engine.progress(elapsed: 40, distance: 0)?.remainingTime == 60)
        #expect(engine.progress(elapsed: 500, distance: 0) == StepProgress(remainingTime: 0, remainingDistance: nil, fraction: 1))
    }

    @Test("the run can start part-way in: the first step starts at the elapsed time and distance given")
    func startOffset() {
        var engine = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [time(60)])], elapsed: 100, distance: 200)
        #expect(engine.update(elapsed: 159, distance: 200).isEmpty)
        #expect(engine.update(elapsed: 160, distance: 200).count == 1)
    }
}

@Suite("Step text (WATCH-104)")
struct StepTextTests {
    private let metric = Locale(identifier: "en_GB_u_ms_metric")
    private let imperial = Locale(identifier: "en_US")

    @Test("time left reads as a clock")
    func timeLeft() {
        func text(_ seconds: TimeInterval) -> String? {
            WatchWorkoutSummary.remainingText(StepProgress(remainingTime: seconds, remainingDistance: nil, fraction: 0), locale: metric)
        }
        #expect(text(83) == "1:23 left")
        #expect(text(9) == "0:09 left")
        #expect(text(0) == "0:00 left")
        #expect(text(82.2) == "1:23 left")
        #expect(text(3725) == "1:02:05 left")
    }

    @Test("with the wrist down a time left is whole minutes, rounded up")
    func remainingValueWithoutSeconds() {
        func value(_ seconds: Double) -> String? {
            WatchWorkoutSummary.remainingValue(
                StepProgress(remainingTime: seconds, remainingDistance: nil, fraction: 0), locale: metric, showsSeconds: false)
        }
        #expect(value(0.4) == "1 min")
        #expect(value(60) == "1 min")
        #expect(value(61) == "2 min")
        #expect(value(59 * 60) == "59 min")
        #expect(value(3600 + 5 * 60 - 10) == "1h05")
        let distance = StepProgress(remainingTime: nil, remainingDistance: 400, fraction: 0)
        #expect(WatchWorkoutSummary.remainingValue(distance, locale: metric, showsSeconds: false)
            == WatchWorkoutSummary.remainingValue(distance, locale: metric))
    }

    @Test("the bare value has no 'left', and remainingText is that value plus ' left'")
    func bareValue() {
        let time = StepProgress(remainingTime: 83, remainingDistance: nil, fraction: 0)
        #expect(WatchWorkoutSummary.remainingValue(time, locale: metric) == "1:23")
        #expect(WatchWorkoutSummary.remainingText(time, locale: metric) == "1:23 left")
        let distance = StepProgress(remainingTime: nil, remainingDistance: 1500, fraction: 0)
        #expect(WatchWorkoutSummary.remainingValue(distance, locale: metric) == "1.5 km")
        #expect(WatchWorkoutSummary.remainingValue(
            StepProgress(remainingTime: nil, remainingDistance: nil, fraction: nil), locale: metric) == nil)
    }

    @Test("distance left follows the locale, and an open step has nothing left")
    func distanceLeft() {
        let distance = StepProgress(remainingTime: nil, remainingDistance: 400, fraction: 0)
        #expect(WatchWorkoutSummary.remainingText(distance, locale: metric) == "400 m left")
        #expect(WatchWorkoutSummary.remainingText(
            StepProgress(remainingTime: nil, remainingDistance: 1500, fraction: 0), locale: metric) == "1.5 km left")
        #expect(WatchWorkoutSummary.remainingText(
            StepProgress(remainingTime: nil, remainingDistance: 1609.344, fraction: 0), locale: imperial) == "1 mi left")
        #expect(WatchWorkoutSummary.remainingText(
            StepProgress(remainingTime: nil, remainingDistance: nil, fraction: nil), locale: metric) == nil)
    }
}

@Suite("WorkoutMetadata (WATCH-104)")
struct WorkoutMetadataTests {
    private func step(_ workoutStep: WorkoutStep, in blocks: [WorkoutBlock]? = nil) -> PlannedStep {
        WorkoutStepEngine(blocks: blocks ?? [WorkoutBlock(steps: [workoutStep])]).steps[0]
    }

    @Test("a workout started from a plan carries the planned activity's ID and the workout's name")
    func workout() {
        let id = UUID()
        let metadata = WorkoutMetadata.workout(plannedActivityID: id, name: "Intervals")
        #expect(metadata[WorkoutMetadata.plannedActivityID] as? String == id.uuidString)
        #expect(metadata[WorkoutMetadata.workoutName] as? String == "Intervals")
        #expect(metadata.count == 2)
    }

    @Test("a time step's segment says where it was, what it was, its goal and how it ended")
    func timeSegment() {
        let blocks = [WorkoutBlock(steps: [time(60, kind: .warmup), time(180, kind: .recovery)], repetitions: 2)]
        let engine = WorkoutStepEngine(blocks: blocks)
        let metadata = WorkoutMetadata.segment(for: engine.steps[3], end: .goalReached)
        #expect(metadata[WorkoutMetadata.stepIndex] as? Int == 3)
        #expect(metadata[WorkoutMetadata.stepKind] as? String == "recovery")
        #expect(metadata[WorkoutMetadata.stepRepetition] as? Int == 2)
        #expect(metadata[WorkoutMetadata.stepRepetitions] as? Int == 2)
        #expect(metadata[WorkoutMetadata.stepGoalType] as? String == "time")
        #expect(metadata[WorkoutMetadata.stepGoalValue] as? Double == 180)
        #expect(metadata[WorkoutMetadata.stepEnd] as? String == "goal")
    }

    @Test("a distance step has its goal in metres, an open step has no goal value")
    func otherGoals() {
        let distanceSegment = WorkoutMetadata.segment(for: step(distance(400)), end: .lap)
        #expect(distanceSegment[WorkoutMetadata.stepGoalType] as? String == "distance")
        #expect(distanceSegment[WorkoutMetadata.stepGoalValue] as? Double == 400)
        #expect(distanceSegment[WorkoutMetadata.stepEnd] as? String == "lap")

        let openSegment = WorkoutMetadata.segment(for: step(open), end: .workoutEnded)
        #expect(openSegment[WorkoutMetadata.stepGoalType] as? String == "open")
        #expect(openSegment[WorkoutMetadata.stepGoalValue] == nil)
        #expect(openSegment[WorkoutMetadata.stepEnd] as? String == "workoutEnded")
    }

    @Test("every key is custom, because HealthKit reserves the ones that start with HK")
    func keysAreCustom() {
        let keys = [
            WorkoutMetadata.plannedActivityID, WorkoutMetadata.workoutName, WorkoutMetadata.stepIndex, WorkoutMetadata.stepKind,
            WorkoutMetadata.stepRepetition, WorkoutMetadata.stepRepetitions, WorkoutMetadata.stepGoalType,
            WorkoutMetadata.stepGoalValue, WorkoutMetadata.stepEnd
        ]
        #expect(keys.allSatisfy { !$0.hasPrefix("HK") })
        #expect(Set(keys).count == keys.count)
    }

    @Test("an engine's end reasons map to what is written")
    func reasonMapping() {
        #expect(WorkoutMetadata.StepEnd(.goalReached) == .goalReached)
        #expect(WorkoutMetadata.StepEnd(.lap) == .lap)
    }
}
