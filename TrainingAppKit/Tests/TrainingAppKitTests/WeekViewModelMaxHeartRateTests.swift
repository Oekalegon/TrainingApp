import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("WeekViewModel max heart rate", .serialized)
struct WeekViewModelMaxHeartRateTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    /// A run at 150 bpm that ramps up 10 bpm per 5 s sample (a real heart's pace, below
    /// TrainingKit's cadence-lock threshold) to hold `peak` for two minutes, then ramps back down.
    private func run(on start: Date, peak: Double) -> Activity {
        let ramp = stride(from: 150.0, to: peak, by: 10).dropFirst().map { $0 }
        let bpms = Array(repeating: 150.0, count: 48) + ramp + Array(repeating: peak, count: 24)
            + ramp.reversed() + Array(repeating: 150.0, count: 48)
        let samples = bpms.enumerated().map { index, bpm in
            HeartRateSample(time: start.addingTimeInterval(Double(index) * 5), bpm: bpm)
        }
        return Activity(source: .healthKit(UUID()), sport: .running, start: start, duration: 600, heartRate: samples)
    }

    private func makeViewModel(
        athleteStore: (any AthleteStore)? = nil,
        history: InMemoryMaxHeartRatePromptHistory = InMemoryMaxHeartRatePromptHistory()
    ) -> (InMemoryStore, TrainingModel, WeekViewModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: athleteStore ?? store
        )
        let model = TrainingModel(stores: stores, athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 178))
        let viewModel = WeekViewModel(
            model: model, refresher: FakeRefresher(), maxHeartRatePromptHistory: history, today: day(3)
        )
        return (store, model, viewModel)
    }

    @Test("a loaded activity above the max produces a suggestion")
    func loadedActivitySuggests() async throws {
        let (store, _, viewModel) = makeViewModel()
        let activity = run(on: day(2), peak: 189)
        try await store.upsert([activity])
        await viewModel.load(asOf: day(3))

        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))

        #expect(viewModel.maxHeartRateSuggestion?.activityID == activity.id)
        #expect(viewModel.maxHeartRateSuggestion?.peakBPM == 189)
    }

    @Test("no suggestion when every activity stays below the max")
    func belowMaxNoSuggestion() async throws {
        let (store, _, viewModel) = makeViewModel()
        try await store.upsert([run(on: day(2), peak: 175)])
        await viewModel.load(asOf: day(3))

        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))

        #expect(viewModel.maxHeartRateSuggestion == nil)
    }

    @Test("a declined activity isn't suggested again")
    func declinedNotSuggestedAgain() async throws {
        let history = InMemoryMaxHeartRatePromptHistory()
        let (store, model, viewModel) = makeViewModel(history: history)
        let activity = run(on: day(2), peak: 189)
        try await store.upsert([activity])
        await viewModel.load(asOf: day(3))
        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))
        let suggestion = try #require(viewModel.maxHeartRateSuggestion)

        viewModel.declineMaxHeartRateSuggestion(suggestion)
        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))

        #expect(viewModel.maxHeartRateSuggestion == nil)
        #expect(history.declinedActivityIDs == [activity.id])
        #expect(model.athlete.currentHeartRateZoneSettings?.maxHeartRateBPM == 178)
    }

    @Test("closing the prompt without choosing asks again on the next check")
    func clearedPromptAsksAgain() async throws {
        let (store, _, viewModel) = makeViewModel()
        try await store.upsert([run(on: day(2), peak: 189)])
        await viewModel.load(asOf: day(3))
        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))

        viewModel.clearMaxHeartRatePrompt()
        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))

        #expect(viewModel.maxHeartRateSuggestion != nil)
    }

    @Test("accepting raises max, persists it, and refreshes the cached stats and load")
    func acceptRaisesAndRefreshesCaches() async throws {
        let (store, model, viewModel) = makeViewModel()
        let activity = run(on: day(2), peak: 189)
        try await store.upsert([activity])
        await viewModel.load(asOf: day(3))
        let weekStart = viewModel.displayedWeekStart
        let statsLoadBefore = try #require(viewModel.sportStatsPages(for: weekStart, asOf: day(3)).first?.load)
        let dailyLoadBefore = viewModel.dailyLoadSplit(for: weekStart, asOf: day(3)).actual.map(\.load).reduce(0, +)
        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))
        let suggestion = try #require(viewModel.maxHeartRateSuggestion)

        await viewModel.acceptMaxHeartRateSuggestion(suggestion, asOf: day(3))

        #expect(viewModel.maxHeartRateSuggestion == nil)
        #expect(model.athlete.currentHeartRateZoneSettings?.maxHeartRateBPM == 189)
        #expect(try await store.athleteProfile()?.currentHeartRateZoneSettings?.maxHeartRateBPM == 189)
        let statsLoadAfter = try #require(viewModel.sportStatsPages(for: weekStart, asOf: day(3)).first?.load)
        let dailyLoadAfter = viewModel.dailyLoadSplit(for: weekStart, asOf: day(3)).actual.map(\.load).reduce(0, +)
        #expect(statsLoadAfter < statsLoadBefore)
        #expect(dailyLoadAfter < dailyLoadBefore)
    }

    @Test("accepting works even after the alert has already cleared the pending suggestion")
    func acceptAfterClearStillApplies() async throws {
        let (store, model, viewModel) = makeViewModel()
        try await store.upsert([run(on: day(2), peak: 189)])
        await viewModel.load(asOf: day(3))
        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))
        let suggestion = try #require(viewModel.maxHeartRateSuggestion)

        viewModel.clearMaxHeartRatePrompt()
        await viewModel.acceptMaxHeartRateSuggestion(suggestion, asOf: day(3))

        #expect(model.athlete.currentHeartRateZoneSettings?.maxHeartRateBPM == 189)
    }

    @Test("a failed save reports the failure and doesn't record a decline")
    func failedSaveReported() async throws {
        let history = InMemoryMaxHeartRatePromptHistory()
        let (store, model, viewModel) = makeViewModel(athleteStore: FailingAthleteSaveStore(), history: history)
        try await store.upsert([run(on: day(2), peak: 189)])
        await viewModel.load(asOf: day(3))
        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))
        let suggestion = try #require(viewModel.maxHeartRateSuggestion)

        await viewModel.acceptMaxHeartRateSuggestion(suggestion, asOf: day(3))

        #expect(viewModel.maxHeartRateUpdateFailed)
        #expect(history.declinedActivityIDs.isEmpty)
        #expect(model.athlete.currentHeartRateZoneSettings?.maxHeartRateBPM == 178)
        viewModel.acknowledgeMaxHeartRateUpdateFailure()
        #expect(!viewModel.maxHeartRateUpdateFailed)
    }

    @Test("the one-time history scan finds an older activity outside the loaded weeks, and runs only once")
    func historyScanRunsOnce() async throws {
        let history = InMemoryMaxHeartRatePromptHistory()
        let (store, _, viewModel) = makeViewModel(history: history)
        let old = run(on: day(-200), peak: 186)
        try await store.upsert([old])
        await viewModel.load(asOf: day(3))

        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))

        #expect(viewModel.maxHeartRateSuggestion?.activityID == old.id)
        #expect(history.hasScannedHistory)

        viewModel.clearMaxHeartRatePrompt()
        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))
        #expect(viewModel.maxHeartRateSuggestion == nil)
    }

    @Test("the history scan ignores activities older than a year")
    func historyScanIgnoresOldActivities() async throws {
        let (store, _, viewModel) = makeViewModel()
        try await store.upsert([run(on: day(-400), peak: 190)])
        await viewModel.load(asOf: day(3))

        await viewModel.checkForMaxHeartRateSuggestion(asOf: day(3))

        #expect(viewModel.maxHeartRateSuggestion == nil)
    }

    @Test("the prompt names the sport, date, peak and current max")
    func promptMessage() {
        let (_, _, viewModel) = makeViewModel()
        let suggestion = MaxHeartRateSuggestion(
            activityID: UUID(), sport: .running, activityStart: day(2), peakBPM: 189, currentMaxBPM: 178
        )

        let message = viewModel.maxHeartRatePromptMessage(for: suggestion)

        // Formatted the same way as the view model, so the test holds in any locale.
        let date = day(2).formatted(
            Date.FormatStyle(calendar: viewModel.athleteCalendar, timeZone: viewModel.athleteTimeZone).day().month(.abbreviated)
        )
        #expect(message.hasPrefix("Your running workout on \(date) held 189 bpm, above your max heart rate of 178 bpm."))
        #expect(message.contains("Update your max heart rate to 189 bpm?"))
    }
}

/// An in-memory ``MaxHeartRatePromptHistory`` for tests.
@MainActor
final class InMemoryMaxHeartRatePromptHistory: MaxHeartRatePromptHistory {
    var declinedActivityIDs: Set<UUID> = []
    var hasScannedHistory = false
}

/// An ``AthleteStore`` whose `save` always fails.
private final class FailingAthleteSaveStore: AthleteStore, @unchecked Sendable {
    struct SaveError: Error {}
    private let base = InMemoryStore()

    func athleteProfile() async throws -> AthleteProfile? { try await base.athleteProfile() }
    func save(_ profile: AthleteProfile) async throws { throw SaveError() }
    func importAnchor() async throws -> ImportAnchor? { try await base.importAnchor() }
    func saveImportAnchor(_ anchor: ImportAnchor?) async throws { try await base.saveImportAnchor(anchor) }
}
