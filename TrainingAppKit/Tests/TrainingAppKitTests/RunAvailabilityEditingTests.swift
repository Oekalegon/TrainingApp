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

    @Test("slots toggle per day, and switching off the last one clears the day")
    func toggleSlot() {
        var availability = RunAvailability().togglingDay(.saturday).togglingDay(.sunday)

        availability = availability.togglingSlot(.morning, on: .saturday)
        #expect(availability[.saturday] == [.afternoonEvening])
        #expect(availability[.sunday] == [.morning, .afternoonEvening])

        availability = availability.togglingSlot(.afternoonEvening, on: .saturday)
        #expect(!availability.isAvailable(on: .saturday))
        #expect(availability.availableWeekdays == [.sunday])

        availability = availability.togglingSlot(.morning, on: .wednesday)
        #expect(availability[.wednesday] == [.morning])
    }

    @Test("weekdays list from the athlete's week start")
    func weekOrder() {
        #expect(Weekday.monday.weekOrder == [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday])
        #expect(Weekday.sunday.weekOrder.first == .sunday)
        #expect(Weekday.saturday.weekOrder == [.saturday, .sunday, .monday, .tuesday, .wednesday, .thursday, .friday])
    }

    @Test("the summary names the days in week order, marking single slots")
    func summary() {
        var athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        athlete.weekStartsOn = .monday
        #expect(AthleteViewModel(athlete: athlete).runAvailabilitySummary == "Not set")

        athlete.runAvailability = RunAvailability(slots: [
            .sunday: [.morning, .afternoonEvening],
            .wednesday: [.morning],
            .monday: [.afternoonEvening],
        ])
        #expect(AthleteViewModel(athlete: athlete).runAvailabilitySummary == "Mon (PM), Wed (AM), Sun")

        athlete.weekStartsOn = .sunday
        #expect(AthleteViewModel(athlete: athlete).runAvailabilitySummary == "Sun, Mon (PM), Wed (AM)")

        athlete.runAvailability = RunAvailability(
            slots: Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0, Set(DaySlot.allCases)) })
        )
        #expect(AthleteViewModel(athlete: athlete).runAvailabilitySummary == "Every day")
    }

    @Test("saved availability is on the profile and in the store, and a fresh model reads it back")
    func persistenceRoundTrip() async throws {
        let (viewModel, model, store) = makeViewModel()
        let availability = RunAvailability().togglingDay(.monday).togglingSlot(.morning, on: .monday)

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
