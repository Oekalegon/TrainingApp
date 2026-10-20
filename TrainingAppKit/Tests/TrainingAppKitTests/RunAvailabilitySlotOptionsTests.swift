import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// MVP5-128: the per-slot options "Long run possible" and "Track available" on the day screen.
@MainActor
@Suite("RunAvailability slot options")
struct RunAvailabilitySlotOptionsTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEditor(_ profile: RunAvailabilityEditorTests.Profile) -> RunAvailabilityEditor {
        RunAvailabilityEditor(saved: { profile.availability }, save: { await profile.save($0) })
    }

    @Test("a slot starts at the defaults: long run possible, no track")
    func defaults() {
        let availability = RunAvailability().togglingDay(.monday)
        for slot in DaySlot.allCases {
            #expect(availability.isOn(.longRunPossible, for: slot, on: .monday))
            #expect(!availability.isOn(.trackAvailable, for: slot, on: .monday))
        }
    }

    @Test("each option toggles on its own slot only")
    func toggles() {
        var availability = RunAvailability().togglingDay(.monday)
        availability = availability.setting(.trackAvailable, to: true, for: .evening, on: .monday)
        availability = availability.setting(.longRunPossible, to: false, for: .morning, on: .monday)

        #expect(availability.isOn(.trackAvailable, for: .evening, on: .monday))
        #expect(!availability.isOn(.trackAvailable, for: .morning, on: .monday))
        #expect(!availability.isOn(.longRunPossible, for: .morning, on: .monday))
        #expect(availability.isOn(.longRunPossible, for: .evening, on: .monday))
        #expect(availability.isOn(.longRunPossible, for: .morning, on: .tuesday))

        availability = availability.setting(.trackAvailable, to: false, for: .evening, on: .monday)
        #expect(!availability.isOn(.trackAvailable, for: .evening, on: .monday))
    }

    @Test("going back to the defaults leaves nothing stored")
    func backToDefaults() {
        let base = RunAvailability().togglingDay(.monday)
        let changed = base.setting(.trackAvailable, to: true, for: .morning, on: .monday)
        #expect(changed != base)
        #expect(changed.setting(.trackAvailable, to: false, for: .morning, on: .monday) == base)
    }

    @Test("options are kept when a slot is switched off and return when it is switched on")
    func keptWhenSlotOff() {
        var availability = RunAvailability().togglingDay(.monday)
            .setting(.trackAvailable, to: true, for: .afternoon, on: .monday)
            .setting(.longRunPossible, to: false, for: .afternoon, on: .monday)
        availability = availability.togglingSlot(.afternoon, on: .monday)
        #expect(!availability[.monday].contains(.afternoon))
        #expect(availability[.monday, .afternoon] == SlotOptions(longRunPossible: false, trackAvailable: true))

        availability = availability.togglingSlot(.afternoon, on: .monday)
        #expect(!availability.isOn(.longRunPossible, for: .afternoon, on: .monday))
        #expect(availability.isOn(.trackAvailable, for: .afternoon, on: .monday))
    }

    @Test("availability stored without slot options reads the defaults")
    func legacy() throws {
        let json = #"{"slots":{"2":["morning","evening"]}}"#
        let decoded = try JSONDecoder().decode(RunAvailability.self, from: Data(json.utf8))
        #expect(decoded.isOn(.longRunPossible, for: .morning, on: .monday))
        #expect(!decoded.isOn(.trackAvailable, for: .morning, on: .monday))
        #expect(decoded.setting(.trackAvailable, to: true, for: .morning, on: .monday)[.monday] == [.morning, .evening])
    }

    @Test("the editor shows an option at once and saves it")
    func editorSaves() async {
        let profile = RunAvailabilityEditorTests.Profile()
        let editor = makeEditor(profile)
        await editor.toggleDay(.thursday)

        await editor.set(.trackAvailable, to: true, for: .evening, on: .thursday)
        await editor.set(.longRunPossible, to: false, for: .morning, on: .thursday)

        #expect(editor.shown.isOn(.trackAvailable, for: .evening, on: .thursday))
        #expect(profile.availability.isOn(.trackAvailable, for: .evening, on: .thursday))
        #expect(!profile.availability.isOn(.longRunPossible, for: .morning, on: .thursday))
        #expect(!editor.didFail)
    }

    @Test("a failed save of an option reverts it and reports it")
    func editorFailure() async {
        let profile = RunAvailabilityEditorTests.Profile()
        let editor = makeEditor(profile)
        await editor.toggleDay(.thursday)

        profile.failing = [2]
        await editor.set(.trackAvailable, to: true, for: .morning, on: .thursday)

        #expect(editor.didFail)
        #expect(!editor.shown.isOn(.trackAvailable, for: .morning, on: .thursday))
        #expect(!profile.availability.isOn(.trackAvailable, for: .morning, on: .thursday))
    }

    @Test("options round trip through the store")
    func persists() async throws {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture(timeZoneIdentifier: "UTC"))
        let viewModel = MicroCycleViewModel(model: model, refresher: FakeRefresher(), today: now)
        let availability = RunAvailability().togglingDay(.sunday)
            .setting(.trackAvailable, to: true, for: .evening, on: .sunday)
            .setting(.longRunPossible, to: false, for: .evening, on: .sunday)

        #expect(await viewModel.setRunAvailability(availability, asOf: now))

        let stored = try #require(try await store.athleteProfile())
        #expect(stored.runAvailability == availability)
        #expect(stored.runAvailability[.sunday, .evening] == SlotOptions(longRunPossible: false, trackAvailable: true))
        #expect(viewModel.athleteViewModel.runAvailability == availability)
    }
}
