import Foundation
import Testing
@testable import TrainingAppKit

@Suite("WorkoutInspectionReport")
struct WorkoutInspectionReportTests {
    private let base = Date(timeIntervalSince1970: 1_699_920_000)  // 2023-11-14T00:00:00Z

    private func workout(
        planID: UUID? = nil, events: [InspectedWorkout.Event] = [], activities: [InspectedWorkout.Activity] = []
    ) -> InspectedWorkout {
        InspectedWorkout(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, activityType: "activityType(37)",
            start: base, end: base.addingTimeInterval(1800), planID: planID,
            planSummary: planID == nil ? nil : "custom workout 'Short interval run', 5 blocks",
            events: events, activities: activities, metadata: [:]
        )
    }

    @Test("a workout with no plan, events or activities says so plainly: that absence is the spike's answer")
    func emptyWorkoutStatesAbsence() {
        let text = WorkoutInspectionReport.format([workout()], generatedAt: base)

        #expect(text.contains("started from plan: no"))
        #expect(text.contains("events: 0"))
        #expect(text.contains("activities: 0"))
        #expect(text.contains("2023-11-14T00:00:00Z to 2023-11-14T00:30:00Z"))
    }

    @Test("a plan-started workout shows the plan's id and summary, events with their times and metadata, and each activity's events")
    func planStartedWorkoutShowsEverything() {
        let planID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let lap = InspectedWorkout.Event(
            type: "lap", start: base.addingTimeInterval(300), end: base.addingTimeInterval(300), metadata: ["step": "2"]
        )
        let segment = InspectedWorkout.Event(
            type: "segment", start: base.addingTimeInterval(600), end: base.addingTimeInterval(660), metadata: [:]
        )
        let activity = InspectedWorkout.Activity(
            activityType: "activityType(37)", start: base, end: nil, events: [segment], metadata: ["b": "2", "a": "1"]
        )

        let text = WorkoutInspectionReport.format(
            [workout(planID: planID, events: [lap], activities: [activity])], generatedAt: base
        )

        #expect(text.contains("started from plan: 22222222-2222-2222-2222-222222222222"))
        #expect(text.contains("plan: custom workout 'Short interval run', 5 blocks"))
        #expect(text.contains("lap  2023-11-14T00:05:00Z  step=2"))  // an instant: one time, not a range
        #expect(text.contains("2023-11-14T00:00:00Z to open"))  // an activity still running has no end
        #expect(text.contains("metadata: a=1, b=2"))  // sorted, so the same workout always reads the same
        #expect(text.contains("segment  2023-11-14T00:10:00Z to 2023-11-14T00:11:00Z"))
    }

    @Test("every workout gets its own section, in the order given")
    func sectionsInOrder() {
        let text = WorkoutInspectionReport.format([workout(), workout(planID: UUID())], generatedAt: base)

        #expect(text.components(separatedBy: "== ").count == 3)
        #expect(text.contains("2 workouts, newest first"))
    }
}
