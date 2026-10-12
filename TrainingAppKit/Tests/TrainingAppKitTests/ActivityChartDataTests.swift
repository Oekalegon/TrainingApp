import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@Suite("ActivityChartData (MVP2-146)")
struct ActivityChartDataTests {
    private let start = Date(timeIntervalSince1970: 1_699_920_000)

    private func hr(_ second: Double, _ bpm: Double) -> HeartRateSample {
        HeartRateSample(time: start.addingTimeInterval(second), bpm: bpm)
    }

    private func speed(_ second: Double, _ metersPerSecond: Double) -> SpeedSample {
        SpeedSample(time: start.addingTimeInterval(second), metersPerSecond: metersPerSecond)
    }

    private func activity(
        duration: TimeInterval = 3600, heartRate: [HeartRateSample] = [], speed: [SpeedSample] = [], steps: [ActivityStep] = []
    ) -> Activity {
        Activity(source: .manual, sport: .running, start: start, duration: duration, heartRate: heartRate, speed: speed, steps: steps)
    }

    private func step(_ keyPath: String, from second: Double, seconds: Double) -> ActivityStep {
        let parts = ActivityStep.components(ofKeyPath: keyPath)!
        return ActivityStep(
            block: parts.block, repetition: parts.repetition, step: parts.step,
            start: start.addingTimeInterval(second), end: start.addingTimeInterval(second + seconds)
        )
    }

    // MARK: Heart rate

    @Test("an hour of one-second heart rate is reduced to a few hundred averaged points, in time order")
    func heartRateReduced() {
        let samples = (0..<3600).map { hr(Double($0), 140 + Double($0 % 10)) }

        let data = ActivityChartData.make(for: activity(heartRate: samples), workout: nil)

        #expect(data.heartRate.count > 300 && data.heartRate.count <= ActivityChartData.maximumPoints)
        #expect(data.heartRate.map(\.elapsed) == data.heartRate.map(\.elapsed).sorted())
        #expect(data.heartRate.allSatisfy { $0.value >= 140 && $0.value <= 149 })
        #expect(data.hasHeartRate)
    }

    @Test("a silence in the heart rate starts a new segment, so the chart draws a gap instead of a line across a pause")
    func heartRateGap() {
        let samples = [hr(0, 130), hr(5, 131), hr(10, 132), hr(200, 120), hr(205, 121)]

        let data = ActivityChartData.make(for: activity(duration: 300, heartRate: samples), workout: nil)

        #expect(Set(data.heartRate.map(\.segment)) == [0, 1])
        #expect(data.heartRate.last?.segment == 1)
    }

    @Test("a source that records a heart rate every minute is one line, not a row of one-point segments")
    func sparseHeartRateIsOneLine() {
        let samples = (0..<60).map { hr(Double($0) * 60, 130 + Double($0 % 5)) }

        let data = ActivityChartData.make(for: activity(duration: 3600, heartRate: samples), workout: nil)

        #expect(Set(data.heartRate.map(\.segment)) == [0])
        #expect(data.heartRate.count == 60)
    }

    @Test("a pause longer than five times the usual spacing still breaks the line, whatever the spacing")
    func gapRelativeToSpacing() {
        // One reading a minute, then nothing for twenty minutes.
        let samples = (0..<10).map { hr(Double($0) * 60, 130) } + (30..<40).map { hr(Double($0) * 60, 130) }

        let data = ActivityChartData.make(for: activity(duration: 2400, heartRate: samples), workout: nil)

        #expect(Set(data.heartRate.map(\.segment)) == [0, 1])
    }

    @Test("readings outside the activity or that aren't heart rates are ignored; none at all is no chart")
    func heartRateFiltered() {
        let data = ActivityChartData.make(for: activity(duration: 100, heartRate: [hr(-5, 120), hr(500, 120), hr(10, 0), hr(20, .nan)]), workout: nil)
        #expect(data.heartRate.isEmpty)
        #expect(!data.hasHeartRate)
        #expect(!ActivityChartData.make(for: activity(), workout: nil).hasHeartRate)
    }

    // MARK: Pace

    @Test("a steady speed is a steady pace, in seconds per kilometer, in one segment")
    func steadyPace() throws {
        let samples = (0..<120).map { speed(Double($0) * 5, 3) }

        let data = ActivityChartData.make(for: activity(duration: 600, speed: samples), workout: nil)

        #expect(data.hasPace)
        #expect(data.pace.allSatisfy { abs($0.value - 333.3) < 5 })
        #expect(Set(data.pace.map(\.segment)) == [0])
        let domain = try #require(data.paceDomain)
        #expect(domain.contains(333))
    }

    @Test("a stop is not a pace: it leaves a gap, and the run after it is a new segment")
    func stopLeavesGap() {
        var samples = (0..<20).map { speed(Double($0) * 5, 3) }
        samples += (20..<40).map { speed(Double($0) * 5, 0) }  // standing still for 100 s
        samples += (40..<60).map { speed(Double($0) * 5, 3) }

        let data = ActivityChartData.make(for: activity(duration: 300, speed: samples), workout: nil)

        #expect(Set(data.pace.map(\.segment)) == [0, 1])
        #expect(!data.pace.contains { $0.elapsed > 110 && $0.elapsed < 190 })
    }

    @Test("a stretch far slower than the rest is drawn at the axis edge instead of squashing the run")
    func slowStretchClamped() throws {
        var samples = (0..<100).map { speed(Double($0) * 5, 3.3) }
        samples += (100..<104).map { speed(Double($0) * 5, 0.8) }  // a short walk: about 21 min/km

        let data = ActivityChartData.make(for: activity(duration: 600, speed: samples), workout: nil)

        let domain = try #require(data.paceDomain)
        #expect(data.pace.allSatisfy { domain.contains($0.value) })
        #expect(domain.upperBound < 1000 / 0.8)  // the walk didn't set the axis
    }

    @Test("no speed, or only a few samples, is no pace chart")
    func noPace() {
        #expect(!ActivityChartData.make(for: activity(), workout: nil).hasPace)
        #expect(ActivityChartData.make(for: activity(), workout: nil).paceDomain == nil)
        #expect(!ActivityChartData.make(for: activity(speed: [speed(0, 3)]), workout: nil).hasPace)
    }

    // MARK: Steps

    private func workout() -> StructuredWorkout {
        StructuredWorkout(name: "Intervals", sport: .running, blocks: [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(300))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(60)), WorkoutStep(kind: .recovery, goal: .time(60))], repetitions: 2),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(300))]),
        ])
    }

    private func recordedSteps() -> [ActivityStep] {
        [
            step("0.0.0", from: 0, seconds: 300),
            step("1.0.0", from: 300, seconds: 60), step("1.0.1", from: 360, seconds: 60),
            step("1.1.0", from: 420, seconds: 60), step("1.1.1", from: 480, seconds: 60),
            step("2.0.0", from: 540, seconds: 300),
        ]
    }

    @Test("recorded steps are spans of the time axis with the role the plan gives each, in order")
    func stepsWithRoles() {
        let data = ActivityChartData.make(for: activity(duration: 840, steps: recordedSteps()), workout: workout())

        #expect(data.steps.count == 6)
        #expect(data.steps.map(\.kind) == [.warmup, .work, .recovery, .work, .recovery, .cooldown])
        #expect(data.steps.map(\.start) == [0, 300, 360, 420, 480, 540])
        #expect(data.steps.last?.end == 840)
        #expect(data.steps.map(\.id) == Array(0..<6))
    }

    @Test("a zero-length step doesn't take the role of the step that starts where it does")
    func zeroLengthStepDoesNotShareARole() {
        let workout = StructuredWorkout(name: "Two", sport: .running, blocks: [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(60))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(60))]),
        ])
        // The warm-up has no time at all, and the work begins at the same instant.
        let steps = [step("0.0.0", from: 0, seconds: 0), step("1.0.0", from: 0, seconds: 60)]

        let data = ActivityChartData.make(for: activity(duration: 60, steps: steps), workout: workout)

        #expect(data.steps.count == 1)
        #expect(data.steps.first?.kind == .work)
    }

    @Test("without the plan's workout, or when the steps don't fit it, the spans have no role")
    func stepsWithoutRoles() {
        let withoutWorkout = ActivityChartData.make(for: activity(duration: 840, steps: recordedSteps()), workout: nil)
        #expect(withoutWorkout.steps.count == 6)
        #expect(withoutWorkout.steps.allSatisfy { $0.kind == nil })

        // The plan was edited to one repetition: the six recorded steps no longer fit it.
        var edited = workout()
        edited.blocks[1] = WorkoutBlock(steps: edited.blocks[1].steps, repetitions: 1)
        let mismatched = ActivityChartData.make(for: activity(duration: 840, steps: recordedSteps()), workout: edited)
        #expect(mismatched.steps.allSatisfy { $0.kind == nil })
    }

    @Test("a step that runs past the activity is clipped to it, and one with no time on the axis is dropped")
    func stepsClipped() {
        let steps = [step("0.0.0", from: 0, seconds: 120), step("1.0.0", from: 80, seconds: 100), step("2.0.0", from: 500, seconds: 30)]

        let data = ActivityChartData.make(for: activity(duration: 100, steps: steps), workout: nil)

        #expect(data.steps.count == 2)
        #expect(data.steps.map(\.end) == [100, 100])
    }

    @Test("time after the last step is a grey stretch of its own at the end, not counted as a step")
    func afterPlanSpan() {
        // The steps end at 840 s; the activity ran on to 1000 s.
        let data = ActivityChartData.make(for: activity(duration: 1000, steps: recordedSteps()), workout: workout())

        #expect(data.steps.count == 7)
        #expect(data.planStepCount == 6)
        let after = data.steps.last
        #expect(after?.isOutsidePlan == true)
        #expect(after?.start == 840 && after?.end == 1000)
        #expect(after?.kind == nil)
        #expect(after?.id == 6)  // one past the last step: the same number its card has
        #expect(data.steps.dropLast().allSatisfy { !$0.isOutsidePlan })
    }

    @Test("a last step that runs to within half a minute of the end leaves no after-plan stretch")
    func noAfterPlanWhenClose() {
        #expect(ActivityChartData.make(for: activity(duration: 860, steps: recordedSteps()), workout: workout()).planStepCount == 6)
        #expect(ActivityChartData.make(for: activity(duration: 860, steps: recordedSteps()), workout: workout()).steps.count == 6)
    }

    @Test("an activity with nothing recorded has nothing to chart")
    func empty() {
        let data = ActivityChartData.make(for: activity(), workout: nil)

        #expect(data.steps.isEmpty && data.heartRate.isEmpty && data.pace.isEmpty)
        #expect(data.duration == 3600)
    }
}

@Suite("ActivityChartData axis ticks (MVP2-146)")
struct ActivityChartDataTickTests {
    @Test("ticks fall on round multiples of the smallest step that keeps them to six or fewer")
    func roundTicks() {
        // 35 minutes: every 10 minutes gives 0, 10, 20, 30.
        #expect(ActivityChartData.niceTicks(in: 0...2100, steps: ActivityChartData.timeTickSteps) == [0, 600, 1200, 1800])
        // 90 seconds: every 30 seconds.
        #expect(ActivityChartData.niceTicks(in: 0...90, steps: ActivityChartData.timeTickSteps) == [0, 30, 60, 90])
        // Pace from 4:50 to 8:35 per km (290 to 515 s): every 60 s would give 5, so it is 60 and starts at 5:00.
        #expect(ActivityChartData.niceTicks(in: 290...515, steps: ActivityChartData.paceTickSteps) == [300, 360, 420, 480])
    }

    @Test("an empty or reversed range has no ticks, and a range wider than the largest step still gets some")
    func edges() {
        #expect(ActivityChartData.niceTicks(in: 5...5, steps: [10]).isEmpty)
        #expect(ActivityChartData.niceTicks(in: 0...100_000, steps: [10, 100], maximumCount: 3).count > 3)
        #expect(ActivityChartData.niceTicks(in: 0...10, steps: []).isEmpty)
    }
}
