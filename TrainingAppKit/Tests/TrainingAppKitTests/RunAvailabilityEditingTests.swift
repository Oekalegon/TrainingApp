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

    @Test("selecting a day offers all three parts and selecting it again clears it")
    func toggleDay() {
        let selected = RunAvailability().togglingDay(.tuesday)
        #expect(selected[.tuesday] == [.morning, .afternoon, .evening])
        #expect(selected.isAvailable(on: .tuesday))

        let cleared = selected.togglingDay(.tuesday)
        #expect(cleared == RunAvailability())
        #expect(!cleared.isAvailable(on: .tuesday))
    }

    @Test("parts toggle independently in any combination, and the last one off clears the day")
    func togglingParts() {
        var availability = RunAvailability().togglingDay(.saturday).togglingDay(.sunday)

        availability = availability.togglingSlot(.afternoon, on: .saturday)
        #expect(availability[.saturday] == [.morning, .evening])
        #expect(availability[.sunday] == [.morning, .afternoon, .evening])

        availability = availability.togglingSlot(.morning, on: .saturday)
        #expect(availability[.saturday] == [.evening])
        #expect(availability.isAvailable(on: .saturday))

        // Turning the last part off switches the day off.
        availability = availability.togglingSlot(.evening, on: .saturday)
        #expect(!availability.isAvailable(on: .saturday))
        #expect(availability == RunAvailability().togglingDay(.sunday))

        // A part turned on for a day that is off selects the day with just that part.
        availability = availability.togglingSlot(.morning, on: .saturday)
        #expect(availability[.saturday] == [.morning])
    }

    @Test("availability stored with the legacy afternoonEvening slot reads as afternoon and evening")
    func legacyPayload() throws {
        let json = #"{"slots":{"2":["morning","afternoonEvening"],"3":["afternoonEvening"]},"slotOptions":{}}"#
        let decoded = try JSONDecoder().decode(RunAvailability.self, from: Data(json.utf8))
        #expect(decoded[.monday] == [.morning, .afternoon, .evening])
        #expect(decoded[.tuesday] == [.afternoon, .evening])

        // The screen edits it like any other, and what is written back no longer has the legacy name.
        let edited = decoded.togglingSlot(.afternoon, on: .tuesday)
        #expect(edited[.tuesday] == [.evening])
        let written = try String(decoding: JSONEncoder().encode(edited), as: UTF8.self)
        #expect(!written.contains("afternoonEvening"))
        #expect(try JSONDecoder().decode(RunAvailability.self, from: Data(written.utf8)) == edited)
    }

    @Test("runs per day default to 1, are capped by the selected parts and survive switching parts off")
    func runsPerDay() {
        var availability = RunAvailability().togglingDay(.saturday)
        #expect(availability.runs(on: .saturday) == 1)
        #expect(availability.maxRuns(on: .saturday) == 3)

        availability = availability.settingRuns(2, on: .saturday)
        #expect(availability.runs(on: .saturday) == 2)
        #expect(availability.runs(on: .monday) == 0)

        // Fewer parts than runs: the stepper's range shrinks and the shown number is capped...
        availability = availability.togglingSlot(.morning, on: .saturday).togglingSlot(.afternoon, on: .saturday)
        #expect(availability.maxRuns(on: .saturday) == 1)
        #expect(availability.runs(on: .saturday) == 1)
        // ...and the stored number returns when the parts do.
        availability = availability.togglingSlot(.morning, on: .saturday)
        #expect(availability.runs(on: .saturday) == 2)

        // Switching the day off and on again starts from the default of 1.
        #expect(availability.togglingDay(.saturday).togglingDay(.saturday).runs(on: .saturday) == 1)
        #expect(availability.togglingDay(.saturday).runsPerDay.isEmpty)

        // Switching the last part off clears the day and its maximum too.
        var parts = RunAvailability().togglingDay(.sunday).settingRuns(3, on: .sunday)
        for slot in DaySlot.allCases { parts = parts.togglingSlot(slot, on: .sunday) }
        #expect(!parts.isAvailable(on: .sunday))
        #expect(parts.runsPerDay.isEmpty)
        #expect(parts.togglingSlot(.morning, on: .sunday).runs(on: .sunday) == 1)

        // Back to 1 removes the stored entry.
        #expect(availability.settingRuns(1, on: .saturday).runsPerDay.isEmpty)
    }

    @Test("availability stored without runsPerDay loads as one run a day")
    func legacyRuns() throws {
        let json = #"{"slots":{"2":["morning","evening"]},"slotOptions":{}}"#
        let decoded = try JSONDecoder().decode(RunAvailability.self, from: Data(json.utf8))
        #expect(decoded.runs(on: .monday) == 1)
    }

    @Test("runs per day round trip through the store")
    func runsPersist() async throws {
        let (viewModel, _, store) = makeViewModel()
        let availability = RunAvailability().togglingDay(.saturday).settingRuns(2, on: .saturday)

        #expect(await viewModel.setRunAvailability(availability, asOf: now))

        let stored = try #require(try await store.athleteProfile())
        #expect(stored.runAvailability.runs(on: .saturday) == 2)
        #expect(viewModel.athleteViewModel.runAvailability.runs(on: .saturday) == 2)
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
        let availability = RunAvailability().togglingDay(.monday).togglingSlot(.afternoon, on: .monday).togglingSlot(.evening, on: .monday)

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

/// MVP5-112: naming run types per weekday.
@Suite("RunAvailability run types")
struct RunAvailabilityRunTypeTests {
    @Test("several types can be named for a weekday and toggled off")
    func toggle() {
        var availability = RunAvailability().togglingDay(.thursday)
        availability = availability.togglingRunType(.interval, on: .thursday).togglingRunType(.threshold, on: .thursday)
        #expect(availability.dayRunTypes[.thursday] == [.interval, .threshold])
        availability = availability.togglingRunType(.interval, on: .thursday)
        #expect(availability.dayRunTypes[.thursday] == [.threshold])
        availability = availability.togglingRunType(.threshold, on: .thursday)
        #expect(availability.dayRunTypes.isEmpty)
    }

    @Test("clearing a weekday leaves the others")
    func clear() {
        let availability = RunAvailability().togglingDay(.sunday).togglingDay(.tuesday)
            .togglingRunType(.long, on: .sunday).togglingRunType(.easy, on: .tuesday)
            .clearingRunTypes(on: .sunday)
        #expect(availability.dayRunTypes == [.tuesday: [.easy]])
    }

    @Test("a named type is tied to its weekdays, the rest are free")
    func tied() {
        let availability = RunAvailability().togglingDay(.sunday).togglingDay(.monday).togglingRunType(.long, on: .sunday)
        #expect(availability.runTypes(on: .sunday).contains(.long))
        #expect(!availability.runTypes(on: .monday).contains(.long))
        #expect(availability.runTypes(on: .monday).contains(.interval))
    }

    @Test("the editor shows a run type at once and saves it")
    @MainActor
    func editor() async {
        var saved = RunAvailability().togglingDay(.friday)
        let editor = RunAvailabilityEditor(saved: { saved }, save: { saved = $0; return true })
        await editor.toggleRunType(.long, on: .friday)
        #expect(editor.shown.dayRunTypes[.friday] == [.long])
        #expect(saved.dayRunTypes[.friday] == [.long])
        await editor.clearRunTypes(on: .friday)
        #expect(saved.dayRunTypes.isEmpty)
    }
}

/// MVP5-112: the line under a weekday in the list.
@Suite("RunAvailability day summary")
struct RunAvailabilitySummaryTests {
    @Test("off, parts only, and with runs and types")
    func summary() {
        var availability = RunAvailability()
        #expect(availability.summary(on: .monday) == "Off")
        availability = availability.togglingDay(.monday)
        #expect(availability.summary(on: .monday) == "Morning, Afternoon, Evening")
        availability = availability.settingRuns(2, on: .monday)
            .togglingRunType(.threshold, on: .monday).togglingRunType(.interval, on: .monday)
        #expect(availability.summary(on: .monday) == "Morning, Afternoon, Evening · 2 runs · Threshold, Interval")
    }
}
