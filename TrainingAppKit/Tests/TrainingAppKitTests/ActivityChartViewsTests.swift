import Foundation
import SwiftUI
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("Activity charts (MVP2-146)")
struct ActivityChartViewsTests {
    private func span(_ id: Int, _ kind: StepKind?) -> ActivityChartData.StepSpan {
        ActivityChartData.StepSpan(id: id, kind: kind, start: Double(id) * 60, end: Double(id + 1) * 60)
    }

    @Test("the legend lists each role once, in the order a workout has them, whatever the order of the steps")
    func legendKinds() {
        let steps = [span(0, .cooldown), span(1, .work), span(2, .recovery), span(3, .work), span(4, .warmup)]

        #expect(ActivityStepLegend.kinds(in: steps) == [.warmup, .work, .recovery, .cooldown])
        #expect(ActivityStepLegend.kinds(in: [span(0, nil), span(1, nil)]).isEmpty)
        #expect(ActivityStepLegend.kinds(in: []).isEmpty)
    }

    @Test("a role has its own colour, and steps with no role alternate so neighbours can be told apart")
    func colours() {
        #expect(Optional(StepKind.warmup).chartColor(index: 0) == .yellow)
        #expect(Optional(StepKind.work).chartColor(index: 3) == .red)
        #expect(Optional(StepKind.recovery).chartColor(index: 1) == .green)
        #expect(Optional(StepKind.cooldown).chartColor(index: 2) == .blue)
        let none: StepKind? = nil
        #expect(none.chartColor(index: 0) != none.chartColor(index: 1))
    }

    @Test("with no step highlighted every band has its usual tint; with one, it is strong and the rest fade")
    func bandOpacities() {
        let work = span(0, .work)
        let unknown = span(1, nil)

        #expect(ActivityStepMarks.bandOpacity(of: work, highlightedID: nil) == 0.18)
        #expect(ActivityStepMarks.bandOpacity(of: unknown, highlightedID: nil) == 0.12)
        #expect(ActivityStepMarks.bandOpacity(of: work, highlightedID: 0) == 0.5)
        #expect(ActivityStepMarks.bandOpacity(of: unknown, highlightedID: 0) == 0.06)
    }

    @Test("a highlight for a step with no band on the chart is ignored, so no band fades for nothing")
    func highlightWithoutABand() {
        let steps = [span(0, .work), span(2, .recovery)]  // step 1 was clipped away

        #expect(ActivityStepMarks.effectiveHighlight(2, in: steps) == 2)
        #expect(ActivityStepMarks.effectiveHighlight(1, in: steps) == nil)
        #expect(ActivityStepMarks.effectiveHighlight(nil, in: steps) == nil)
    }

    @Test("tapping a step's card selects it, tapping it again clears it, and tapping another moves the highlight")
    func toggling() {
        #expect(WorkoutStepCardList.toggled(nil, tapping: 3) == 3)
        #expect(WorkoutStepCardList.toggled(3, tapping: 3) == nil)
        #expect(WorkoutStepCardList.toggled(3, tapping: 5) == 5)
    }

    @Test("the chart summary says which step is highlighted, counting from 1, and only when it is on the chart")
    func highlightSpoken() {
        let start = Date(timeIntervalSince1970: 0)
        let hr = (0..<20).map { HeartRateSample(time: start.addingTimeInterval(Double($0) * 5), bpm: 120) }
        let steps = [
            ActivityStep(block: 0, repetition: 0, step: 0, start: start, end: start.addingTimeInterval(50)),
            ActivityStep(block: 1, repetition: 0, step: 0, start: start.addingTimeInterval(50), end: start.addingTimeInterval(100)),
        ]
        let data = ActivityChartData.make(for: Activity(source: .manual, sport: .running, start: start, duration: 100, heartRate: hr, steps: steps), workout: nil)

        #expect(ActivityHeartRateChart.spokenSummary(of: data, highlightedStepID: 1).hasSuffix(", step 2 highlighted"))
        #expect(!ActivityHeartRateChart.spokenSummary(of: data, highlightedStepID: 9).contains("highlighted"))
        #expect(!ActivityHeartRateChart.spokenSummary(of: data).contains("highlighted"))
    }

    @Test("pace on the axis is minutes and seconds in the device's unit, without the unit")
    func axisText() {
        #expect(ActivityPaceChart.axisText(secondsPerKilometer: 392.4, in: .metric) == "6:32")
        #expect(ActivityPaceChart.axisText(secondsPerKilometer: 392.4, in: .imperial) == "10:32")
    }

    @Test("VoiceOver hears the range, the unit and how many steps are marked, or that nothing was recorded")
    func spokenSummaries() {
        let start = Date(timeIntervalSince1970: 0)
        let hr = (0..<60).map { HeartRateSample(time: start.addingTimeInterval(Double($0) * 5), bpm: 110 + Double($0)) }
        let speed = (0..<60).map { SpeedSample(time: start.addingTimeInterval(Double($0) * 5), metersPerSecond: 3) }
        let step = ActivityStep(block: 0, repetition: 0, step: 0, start: start, end: start.addingTimeInterval(100))
        let activity = Activity(source: .manual, sport: .running, start: start, duration: 300, heartRate: hr, speed: speed, steps: [step])

        let data = ActivityChartData.make(for: activity, workout: nil)

        #expect(ActivityHeartRateChart.spokenSummary(of: data).hasPrefix("From 11"))
        #expect(ActivityHeartRateChart.spokenSummary(of: data).hasSuffix("1 steps marked"))
        #expect(ActivityPaceChart.spokenSummary(of: data, in: .metric).contains("per kilometer"))
        #expect(ActivityPaceChart.spokenSummary(of: data, in: .imperial).contains("per mile"))
        let empty = ActivityChartData.make(for: Activity(source: .manual, sport: .running, start: start, duration: 60), workout: nil)
        #expect(ActivityHeartRateChart.spokenSummary(of: empty) == "No heart rate recorded")
        #expect(ActivityPaceChart.spokenSummary(of: empty, in: .metric) == "No pace recorded")
    }
}
