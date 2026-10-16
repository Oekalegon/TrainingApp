import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// MVP5-105: the athlete sets when they can run from the Athlete tab.
@MainActor
@Suite("Running availability editing")
struct RunAvailabilityEditingTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeViewModel(
        athleteStore: (any AthleteStore)? = nil
    ) -> (MicroCycleViewModel, TrainingModel, InMemoryStore) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: athleteStore ?? store
        )
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture(timeZoneIdentifier: "UTC"))
        return (MicroCycleViewModel(model: model, refresher: FakeRefresher(), today: now), model, store)
    }

    @Test("selecting a day offers both slots and selecting it again clears it")
    func toggleDay() {
        let selected = RunAvailability().togglingDay(.tuesday)
        #expect(selected[.tuesday] == [.morning, .afternoonEvening])
        #expect(selected.isAvailable(on: .tuesday))

        let cleared = selected.togglingDay(.tuesday)
        #expect(cleared == RunAvailability())
        #expect(!cleared.isAvailable(on: .tuesday))
    }

    @Test("a selected day can be narrowed to one slot and widened again, staying selected")
    func narrowing() {
        var availability = RunAvailability().togglingDay(.saturday).togglingDay(.sunday)
        #expect(availability.slotChoice(on: .saturday) == .anyTime)

        availability = availability.settingSlots(.morning, on: .saturday)
        #expect(availability[.saturday] == [.morning])
        #expect(availability.slotChoice(on: .saturday) == .morning)
        #expect(availability[.sunday] == [.morning, .afternoonEvening])

        availability = availability.settingSlots(.afternoonEvening, on: .saturday)
        #expect(availability.slotChoice(on: .saturday) == .afternoonEvening)

        availability = availability.settingSlots(.anyTime, on: .saturday)
        #expect(availability[.saturday] == [.morning, .afternoonEvening])
        #expect(availability.slotChoice(on: .wednesday) == .anyTime)
    }

    @Test("weekdays list from the athlete's week start")
    func weekOrder() {
        #expect(Weekday.monday.weekOrder == [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday])
        #expect(Weekday.sunday.weekOrder.first == .sunday)
        #expect(Weekday.saturday.weekOrder == [.saturday, .sunday, .monday, .tuesday, .wednesday, .thursday, .friday])
    }

    @Test("saved availability is on the profile and in the store, and a fresh model reads it back")
    func persistenceRoundTrip() async throws {
        let (viewModel, model, store) = makeViewModel()
        let availability = RunAvailability().togglingDay(.monday).settingSlots(.morning, on: .monday)

        #expect(await viewModel.setRunAvailability(availability, asOf: now))

        #expect(model.athlete.runAvailability == availability)
        #expect(viewModel.athleteViewModel.runAvailability == availability)
        let stored = try #require(try await store.athleteProfile())
        #expect(stored.runAvailability == availability)
        // The profile is what new plans read their availability from.
        #expect(PlanPreferences(runAvailability: stored.runAvailability).runAvailability == availability)

        // Clearing the last day saves an empty availability.
        #expect(await viewModel.setRunAvailability(availability.togglingDay(.monday), asOf: now))
        #expect(try await store.athleteProfile()?.runAvailability == RunAvailability())
    }

    @Test("a failed save changes nothing and says so")
    func failedSave() async {
        let base = InMemoryStore()
        let failing = FailingAthleteStore(base: base)
        let (viewModel, model, _) = makeViewModel(athleteStore: failing)
        await failing.setFailsSaves(true)
        let before = model.athlete

        #expect(await viewModel.setRunAvailability(RunAvailability().togglingDay(.friday), asOf: now) == false)

        #expect(model.athlete == before)
        #expect(viewModel.athleteViewModel.runAvailability == RunAvailability())
    }
}
