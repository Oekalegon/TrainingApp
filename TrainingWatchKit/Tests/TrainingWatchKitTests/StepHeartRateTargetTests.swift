import Foundation
import Testing
import TrainingCore
@testable import TrainingWatchKit

@Suite("StepHeartRateTarget (WATCH-105)")
struct StepHeartRateTargetTests {
    private let bands = ZoneBands(zones: WatchZones(settings: .init(
        effectiveDate: .distantPast, restingHeartRateBPM: 55, maxHeartRateBPM: 190)))!

    private func step(_ target: IntensityTarget?, companion: IntensityTarget? = nil) -> WorkoutStep {
        WorkoutStep(kind: .work, goal: .time(60), target: target, companionTarget: companion)
    }

    @Test("a zone resolves to its bpm range and a Z label")
    func zone() throws {
        let target = try #require(StepHeartRateTarget(step: step(.heartRateZone(4)), bands: bands))
        #expect(target.label == "Z4")
        #expect(target.bpm == bands.range(of: 4))
    }

    @Test("a stretch of zones is worked out from zone positions; a whole zone reads as one zone")
    func zoneRange() throws {
        let zone4 = try #require(bands.range(of: 4))
        let zone5 = try #require(bands.range(of: 5))
        let half = try #require(StepHeartRateTarget(step: step(.heartRateZoneRange(4.0...4.5)), bands: bands))
        #expect(half.label == "Z4.0-4.5")
        #expect(half.bpm.lowerBound == zone4.lowerBound)
        #expect(abs(half.bpm.upperBound - (zone4.lowerBound + (zone4.upperBound - zone4.lowerBound) / 2)) < 0.001)

        let whole = try #require(StepHeartRateTarget(step: step(.heartRateZoneRange(4.0...5.0)), bands: bands))
        #expect(whole.label == "Z4")
        #expect(whole.bpm == zone4.lowerBound...zone5.lowerBound)

        let top = try #require(StepHeartRateTarget(step: step(.heartRateZoneRange(5.5...6.0)), bands: bands))
        #expect(top.bpm.upperBound == zone5.upperBound)
    }

    @Test("a bpm range needs no zones")
    func bpmRange() throws {
        let target = try #require(StepHeartRateTarget(step: step(.heartRateRange(150, 160)), bands: nil))
        #expect(target.label == "150-160 bpm")
        #expect(target.bpm == 150...160)
    }

    @Test("a zone target without zones, and steps with no heart-rate target, have none")
    func none() {
        #expect(StepHeartRateTarget(step: step(.heartRateZone(2)), bands: nil) == nil)
        #expect(StepHeartRateTarget(step: step(nil), bands: bands) == nil)
        #expect(StepHeartRateTarget(step: step(.rpe(5)), bands: bands) == nil)
        #expect(StepHeartRateTarget(step: step(.pace(300...330)), bands: bands) == nil)
    }

    @Test("zone positions outside 1 to 6 are clamped, and a reversed or zero-width range still works")
    func edges() throws {
        let zone1 = try #require(bands.range(of: 1))
        let zone5 = try #require(bands.range(of: 5))
        let low = try #require(StepHeartRateTarget(step: step(.heartRateZoneRange(0.5...2.0)), bands: bands))
        #expect(low.bpm.lowerBound == zone1.lowerBound)
        let top = try #require(StepHeartRateTarget(step: step(.heartRateZoneRange(5.0...7.0)), bands: bands))
        #expect(top.bpm.upperBound == zone5.upperBound)

        let reversed = try #require(StepHeartRateTarget(step: step(.heartRateRange(160, 150)), bands: nil))
        #expect(reversed.bpm == 150...160)
        let flat = try #require(StepHeartRateTarget(step: step(.heartRateRange(150, 150)), bands: nil))
        #expect(flat.gaugePosition(forHeartRate: 150) == 0.25)
    }

    @Test("a pace step with a heart-rate companion uses the companion")
    func companion() throws {
        let target = try #require(StepHeartRateTarget(step: step(.pace(300...330), companion: .heartRateZone(3)), bands: bands))
        #expect(target.label == "Z3")
    }

    @Test("a reading is below, inside (bounds included) or above, by how many bpm")
    func position() throws {
        let target = try #require(StepHeartRateTarget(step: step(.heartRateRange(150, 160)), bands: nil))
        #expect(target.position(forHeartRate: 142.5) == .below(7.5))
        #expect(target.position(forHeartRate: 150) == .inside)
        #expect(target.position(forHeartRate: 160) == .inside)
        #expect(target.position(forHeartRate: 163) == .above(3))
        #expect(target.position(forHeartRate: 142.5).text == "8 bpm below")
        #expect(target.position(forHeartRate: 155).text == "In target")
        #expect(target.position(forHeartRate: 163).text == "3 bpm above")
    }

    @Test("the gauge puts the target in its middle half and clamps far-off readings")
    func gauge() throws {
        let target = try #require(StepHeartRateTarget(step: step(.heartRateRange(150, 160)), bands: nil))
        #expect(target.gaugePosition(forHeartRate: 150) == 0.25)
        #expect(target.gaugePosition(forHeartRate: 160) == 0.75)
        #expect(target.gaugePosition(forHeartRate: 155) == 0.5)
        #expect(target.gaugePosition(forHeartRate: 60) == 0)
        #expect(target.gaugePosition(forHeartRate: 220) == 1)
    }
}

@Suite("Next step text (WATCH-105)")
struct NextStepTextTests {
    private let metric = Locale(identifier: "en_NL")

    @Test("says what comes next, then 'Last step', then nothing once done")
    func next() {
        var engine = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [
            WorkoutStep(kind: .work, goal: .time(60), target: .heartRateZone(4)),
            WorkoutStep(kind: .recovery, goal: .time(30), target: .heartRateZone(2))
        ])])
        #expect(WatchWorkoutSummary.nextText(engine, locale: metric) == "Next: Recovery 30 s Z2")
        _ = engine.lap(elapsed: 5, distance: 0)
        #expect(WatchWorkoutSummary.nextText(engine, locale: metric) == "Last step")
        _ = engine.lap(elapsed: 9, distance: 0)
        #expect(WatchWorkoutSummary.nextText(engine, locale: metric) == nil)
    }
}
