import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("MicroCycleViewModel field tests (MVP2-155)", .serialized)
struct MicroCycleViewModelFieldTestTests {
    private struct StubImporter: ActivityImporting {
        let activities: [Activity]
        func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
            ImportResult(upserted: activities, deletedSources: [], anchor: nil)
        }
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
        history: InMemoryMaxHeartRatePromptHistory = InMemoryMaxHeartRatePromptHistory(),
        athleteStore: (any AthleteStore)? = nil, wrappingActivityStore: ((InMemoryStore) -> any ActivityStore)? = nil,
        activity makeActivity: ((UUID) -> Activity)? = nil,
        workoutSeconds: Double = 600, maxSource: MaxHeartRateSource = .formula
    ) async throws -> (TrainingModel, MicroCycleViewModel, Activity) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: wrappingActivityStore?(store) ?? store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: athleteStore ?? store
        )
        var athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 178)
        athlete.heartRateZoneHistory[0].maxHeartRateSource = maxSource
        let model = TrainingModel(stores: stores, athlete: athlete)
        let workout = StructuredWorkout(
            name: "Test", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(workoutSeconds))])], purpose: purpose
        )
        try await model.add(workout, asOf: day(2))
        let plan = PlannedActivity(workoutID: workout.id, date: day(2))
        try await model.add(plan, asOf: day(2))
        try await model.load(in: day(0)...day(6), asOf: day(2))
        let activity = makeActivity?(plan.id) ?? run(on: day(2), peak: peak, scheduledPlanID: plan.id)
        try await model.importActivities(from: StubImporter(activities: [activity]), asOf: day(2))
        let viewModel = MicroCycleViewModel(
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

        await viewModel.checkForFieldTestResult()

        #expect(viewModel.fieldTestResult == nil)
    }

    /// A 30-minute effort at a steady `bpm`, one sample every 5 s.
    private func thirtyMinuteEffort(bpm: Double) -> (UUID) -> Activity {
        { planID in
            let start = day(2)
            let samples = (0..<360).map { HeartRateSample(time: start.addingTimeInterval(Double($0) * 5), bpm: bpm) }
            return Activity(
                source: .healthKit(UUID()), sport: .running, start: start, duration: 1800,
                heartRate: samples, scheduledPlanID: planID
            )
        }
    }

    @Test("a lactate threshold test is offered, with no value on record to compare")
    func lactateThresholdOffered() async throws {
        let (model, viewModel, activity) = try await makeViewModel(
            purpose: .lthrTest, activity: thirtyMinuteEffort(bpm: 162), workoutSeconds: 1800
        )

        await viewModel.checkForFieldTestResult()

        let result = try #require(viewModel.fieldTestResult)
        #expect(result.measurement == .lactateThresholdHeartRate)
        #expect(result.valueBPM == 162)
        #expect(result.currentBPM == nil)
        #expect(viewModel.fieldTestPromptTitle(for: result) == "New Lactate Threshold?")
        #expect(viewModel.fieldTestAcceptTitle(for: result) == "Update to 162 bpm")
        #expect(viewModel.fieldTestPromptMessage(for: result).contains("no lactate threshold heart rate on record"))

        await viewModel.acceptFieldTestResult(result, asOf: day(3))

        let settings = try #require(model.athlete.heartRateZoneSettings(asOf: activity.start))
        #expect(settings.lactateThresholdHeartRateBPM == 162)
        #expect(settings.lactateThresholdSource == .fieldTest(activityID: activity.id))
        #expect(settings.maxHeartRateBPM == 178)
    }

    @Test("a result equal to the current max is still offered, to record it as measured")
    func equalResultIsOffered() async throws {
        let (_, viewModel, _) = try await makeViewModel(peak: 178)

        await viewModel.checkForFieldTestResult()

        let result = try #require(viewModel.fieldTestResult)
        #expect(viewModel.fieldTestAcceptTitle(for: result) == "Record 178 bpm")
        #expect(viewModel.fieldTestPromptMessage(for: result).contains("the same as your max heart rate"))
    }

    @Test("an equal result isn't offered over a lab-tested value, since it would only swap in a weaker source")
    func equalResultOverLabTestIsNotOffered() async throws {
        let labDay = day(-30)
        let (model, viewModel, _) = try await makeViewModel(peak: 178, maxSource: .labTest(measuredOn: labDay))

        await viewModel.checkForFieldTestResult()

        #expect(viewModel.fieldTestResult == nil)
        #expect(model.athlete.currentHeartRateZoneSettings?.maxHeartRateSource == .labTest(measuredOn: labDay))
    }

    @Test("a different result over a lab-tested value is offered, with the note")
    func differentResultOverLabTestIsOffered() async throws {
        let (_, viewModel, _) = try await makeViewModel(peak: 171, maxSource: .labTest(measuredOn: day(-30)))

        await viewModel.checkForFieldTestResult()

        let result = try #require(viewModel.fieldTestResult)
        #expect(result.replacesMoreReliableSource)
        #expect(viewModel.fieldTestPromptMessage(for: result).contains("This replaces a lab-tested value."))
    }

    @Test("the message names the direction, and says when the effort was placed by the plan")
    func messageBranches() {
        let viewModel = FieldTestMessageFixture.viewModel()
        let base = FieldTestResult(
            measurement: .maxHeartRate, activityID: UUID(), activityStart: day(2), valueBPM: 189, currentBPM: 178
        )
        #expect(viewModel.fieldTestPromptMessage(for: base).contains("above your max heart rate of 178 bpm"))
        #expect(!viewModel.fieldTestPromptMessage(for: base).contains("scheduled workout"))
        let estimated = FieldTestResult(
            measurement: .maxHeartRate, activityID: UUID(), activityStart: day(2), valueBPM: 189, currentBPM: 178,
            isEstimatedFromPlan: true
        )
        #expect(viewModel.fieldTestPromptMessage(for: estimated).contains("scheduled workout"))
    }

    @Test("a test that can't be measured is skipped without a prompt, and not measured again until an import")
    func unmeasurableIsSkipped() async throws {
        // A lactate threshold test whose activity has the wrong shape: a ten-minute run.
        let (_, viewModel, activity) = try await makeViewModel(purpose: .lthrTest, peak: 171)

        await viewModel.checkForFieldTestResult()

        #expect(viewModel.fieldTestResult == nil)
        #expect(!viewModel.fieldTestUpdateFailed)
        #expect(viewModel.fieldTestFailures[activity.id] != nil)
        #expect(viewModel.activityDetailViewModel(for: activity).fieldTestFailureMessage == viewModel.fieldTestFailures[activity.id]?.explanation)

        await viewModel.refreshPeriodCachesIfNeeded(asOf: day(3), activitiesChanged: true)
        #expect(viewModel.fieldTestFailures.isEmpty)
        #expect(viewModel.activityDetailViewModel(for: activity).fieldTestFailureMessage == nil)
    }

    @Test("every reason a test couldn't be measured has its own explanation, with a way forward")
    func explanations() {
        let errors: [FieldTestError] = [
            .noHeartRate, .effortNotLocated, .effortTooShort(recordedSeconds: 600),
            .insufficientHeartRate, .implausibleValue(bpm: 48)
        ]
        let texts = errors.map(\.explanation)
        #expect(Set(texts).count == errors.count)
        #expect(texts[1].contains("Start the test from its scheduled workout"))
        #expect(texts[2].contains("10 minutes"))
        #expect(texts[4].contains("48 bpm"))
    }

    @Test("a measured test, or an ordinary workout, has no failure on its detail sheet")
    func noFailureWhenMeasured() async throws {
        let (_, viewModel, activity) = try await makeViewModel(peak: 171)
        await viewModel.checkForFieldTestResult()

        #expect(viewModel.fieldTestResult != nil)
        #expect(viewModel.activityDetailViewModel(for: activity).fieldTestFailureMessage == nil)
    }

    @Test("a store failure while measuring isn't remembered as a failed test, and is retried")
    func storeFailureIsRetried() async throws {
        var failingStore: FailingActivityStore?
        let (_, viewModel, activity) = try await makeViewModel(peak: 171, wrappingActivityStore: {
            let failing = FailingActivityStore(base: $0)
            failingStore = failing
            return failing
        })
        let failing = try #require(failingStore)
        await failing.setFailsIDReads(true)

        await viewModel.checkForFieldTestResult()

        #expect(viewModel.fieldTestResult == nil)
        #expect(viewModel.fieldTestFailures.isEmpty)
        #expect(viewModel.activityDetailViewModel(for: activity).fieldTestFailureMessage == nil)

        await failing.setFailsIDReads(false)
        await viewModel.checkForFieldTestResult()

        #expect(viewModel.fieldTestResult != nil)
    }

    @Test("linking or unlinking a test activity looks again, so the sheet's message follows the link")
    func failureFollowsTheLink() async throws {
        let (_, viewModel, activity) = try await makeViewModel(purpose: .lthrTest, peak: 171)
        await viewModel.checkForFieldTestResult()
        let planID = try #require(activity.linkedPlanID)
        #expect(viewModel.fieldTestFailures[activity.id] != nil)

        await viewModel.unlinkActivity(activity, asOf: day(3))
        #expect(viewModel.fieldTestFailures[activity.id] == nil)

        let unlinked = try #require(viewModel.model.activities.first { $0.id == activity.id })
        await viewModel.linkActivity(unlinked, toPlan: planID, asOf: day(3))
        #expect(viewModel.fieldTestFailures[activity.id] != nil)
    }

    @Test("a failed save reports the failure, changes nothing and doesn't record a decline")
    func failedSaveReported() async throws {
        let history = InMemoryMaxHeartRatePromptHistory()
        let (model, viewModel, _) = try await makeViewModel(
            peak: 171, history: history, athleteStore: FailingAthleteSaveStore()
        )
        await viewModel.checkForFieldTestResult()
        let result = try #require(viewModel.fieldTestResult)

        await viewModel.acceptFieldTestResult(result, asOf: day(3))

        #expect(viewModel.fieldTestUpdateFailed)
        #expect(history.declinedActivityIDs.isEmpty)
        #expect(model.athlete.currentHeartRateZoneSettings?.maxHeartRateBPM == 178)
        viewModel.acknowledgeFieldTestUpdateFailure()
        #expect(!viewModel.fieldTestUpdateFailed)

        await viewModel.checkForFieldTestResult()
        #expect(viewModel.fieldTestResult != nil)
    }

    @Test("a declined test also keeps its activity from being suggested as a raise")
    func declinedTestIsNotSuggestedAsRaise() async throws {
        let (_, viewModel, _) = try await makeViewModel(peak: 189)
        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))
        viewModel.declineFieldTestResult(try #require(viewModel.fieldTestResult))

        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))

        #expect(viewModel.fieldTestResult == nil)
        #expect(viewModel.maxHeartRateSuggestion == nil)
    }

    @Test("the athlete screen says a max came from a field test")
    func athleteCaption() async throws {
        let (model, viewModel, _) = try await makeViewModel(peak: 171)
        await viewModel.checkForFieldTestResult()
        await viewModel.acceptFieldTestResult(try #require(viewModel.fieldTestResult), asOf: day(3))

        let caption = AthleteViewModel(athlete: model.athlete).maxHeartRateSourceDescription

        #expect(caption?.hasPrefix("Measured in a field test on") == true)
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }
}

@MainActor
private enum FieldTestMessageFixture {
    static func viewModel() -> MicroCycleViewModel {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 178))
        return MicroCycleViewModel(model: model, refresher: FakeRefresher(), today: .now)
    }
}
