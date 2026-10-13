import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("WeekViewModel field tests (MVP2-155)", .serialized)
struct WeekViewModelFieldTestTests {
    private struct StubImporter: ActivityImporting {
        let activities: [Activity]
        func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
            ImportResult(upserted: activities, deletedSources: [], anchor: nil)
        }
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    /// A run at 150 bpm that ramps up to hold `peak` for two minutes, then ramps back down.
    private func run(on start: Date, peak: Double, scheduledPlanID: UUID?) -> Activity {
        let ramp = stride(from: 150.0, to: peak, by: 10).dropFirst().map { $0 }
        let bpms = Array(repeating: 150.0, count: 48) + ramp + Array(repeating: peak, count: 24)
            + ramp.reversed() + Array(repeating: 150.0, count: 48)
        let samples = bpms.enumerated().map { index, bpm in
            HeartRateSample(time: start.addingTimeInterval(Double(index) * 5), bpm: bpm)
        }
        return Activity(
            source: .healthKit(UUID()), sport: .running, start: start, duration: 600,
            heartRate: samples, scheduledPlanID: scheduledPlanID
        )
    }

    /// A view model with a planned workout of `purpose` on day 2 and an activity of that day with the
    /// given peak, imported (so it's linked to the plan, as in the app). The athlete's max is 178.
    private func makeViewModel(
        purpose: WorkoutPurpose = .maxHRTest, peak: Double = 171,
        history: InMemoryMaxHeartRatePromptHistory = InMemoryMaxHeartRatePromptHistory()
    ) async throws -> (TrainingModel, WeekViewModel, Activity) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 178))
        let workout = StructuredWorkout(
            name: "Test", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(600))])], purpose: purpose
        )
        try await model.add(workout, asOf: day(2))
        let plan = PlannedActivity(workoutID: workout.id, date: day(2))
        try await model.add(plan, asOf: day(2))
        try await model.load(in: day(0)...day(6), asOf: day(2))
        let activity = run(on: day(2), peak: peak, scheduledPlanID: plan.id)
        try await model.importActivities(from: StubImporter(activities: [activity]), asOf: day(2))
        let viewModel = WeekViewModel(
            model: model, refresher: FakeRefresher(), maxHeartRatePromptHistory: history, today: day(3)
        )
        await viewModel.load(asOf: day(3))
        return (model, viewModel, model.activities[0])
    }

    @Test("a max heart rate test below the current max is offered, as a lower value")
    func lowerResultIsOffered() async throws {
        let (_, viewModel, activity) = try await makeViewModel(peak: 171)

        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))

        let result = try #require(viewModel.fieldTestResult)
        #expect(result.activityID == activity.id)
        #expect(result.valueBPM == 171)
        #expect(result.currentBPM == 178)
        #expect(viewModel.maxHeartRateSuggestion == nil)
        #expect(viewModel.fieldTestPromptMessage(for: result).contains("below your max heart rate of 178 bpm"))
    }

    @Test("a test that reached a higher max is offered as a field-test result, not a workout suggestion")
    func higherResultIsAFieldTest() async throws {
        let (_, viewModel, _) = try await makeViewModel(peak: 189)

        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))

        #expect(viewModel.fieldTestResult?.valueBPM == 189)
        #expect(viewModel.maxHeartRateSuggestion == nil)
    }

    @Test("accepting sets the max from the test's day, with the field-test source")
    func acceptApplies() async throws {
        let (model, viewModel, activity) = try await makeViewModel(peak: 171)
        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))
        let result = try #require(viewModel.fieldTestResult)

        await viewModel.acceptFieldTestResult(result, asOf: day(3))

        let settings = try #require(model.athlete.heartRateZoneSettings(asOf: activity.start))
        #expect(settings.maxHeartRateBPM == 171)
        #expect(settings.maxHeartRateSource == .fieldTest(activityID: activity.id))
        #expect(viewModel.fieldTestResult == nil)
        #expect(!viewModel.fieldTestUpdateFailed)

        // It isn't asked about again once applied.
        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))
        #expect(viewModel.fieldTestResult == nil)
    }

    @Test("keeping the current value leaves the max alone and isn't asked again")
    func declineKeeps() async throws {
        let history = InMemoryMaxHeartRatePromptHistory()
        let (model, viewModel, activity) = try await makeViewModel(peak: 171, history: history)
        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))
        let result = try #require(viewModel.fieldTestResult)

        viewModel.declineFieldTestResult(result)
        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))

        #expect(viewModel.fieldTestResult == nil)
        #expect(history.declinedActivityIDs.contains(activity.id))
        #expect(model.athlete.currentHeartRateZoneSettings?.maxHeartRateBPM == 178)
    }

    @Test("dismissing without a choice asks again on the next check")
    func dismissAsksAgain() async throws {
        let (_, viewModel, _) = try await makeViewModel(peak: 171)
        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))

        viewModel.clearFieldTestPrompt()
        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))

        #expect(viewModel.fieldTestResult != nil)
    }

    @Test("a workout that isn't a test is never offered as one")
    func ordinaryWorkoutIsNotATest() async throws {
        let (_, viewModel, _) = try await makeViewModel(purpose: .general, peak: 171)

        await viewModel.checkForFieldTestResult(asOf: day(3))

        #expect(viewModel.fieldTestResult == nil)
    }

    @Test("a test that can't be measured is skipped without a prompt")
    func unmeasurableIsSkipped() async throws {
        let (_, viewModel, _) = try await makeViewModel(purpose: .lthrTest, peak: 171)

        await viewModel.checkForFieldTestResult(asOf: day(3))

        #expect(viewModel.fieldTestResult == nil)
        #expect(!viewModel.fieldTestUpdateFailed)
    }
}
