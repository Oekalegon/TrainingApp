import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// MVP5-128: the per-day "Track available" switch on the day screen, stored as slot options.
@MainActor
@Suite("RunAvailability track option")
struct RunAvailabilitySlotOptionsTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEditor(_ profile: RunAvailabilityEditorTests.Profile) -> RunAvailabilityEditor {
        RunAvailabilityEditor(saved: { profile.availability }, save: { await profile.save($0) })
    }

    @Test("a day starts without a track")
    func defaults() {
        let availability = RunAvailability().togglingDay(.monday)
        #expect(!availability.hasTrack(on: .monday))
        #expect(!availability.hasTrack(on: .tuesday))
    }

    @Test("the switch sets the track on every part of that day only")
    func toggles() {
        let availability = RunAvailability().togglingDay(.monday).togglingDay(.tuesday)
            .settingTrack(true, on: .monday)

        #expect(availability.hasTrack(on: .monday))
        for slot in DaySlot.allCases { #expect(availability[.monday, slot].trackAvailable) }
        #expect(!availability.hasTrack(on: .tuesday))
        // The long run option is not touched.
        #expect(availability[.monday, .morning].longRunPossible)

        #expect(!availability.settingTrack(false, on: .monday).hasTrack(on: .monday))
    }

    @Test("switching the track off leaves nothing stored")
    func backToDefaults() {
        let base = RunAvailability().togglingDay(.monday)
        #expect(base.settingTrack(true, on: .monday).settingTrack(false, on: .monday) == base)
    }

    @Test("a long run option stored earlier is kept")
    func keepsLongRunOption() {
        var availability = RunAvailability().togglingDay(.monday)
        availability[.monday, .evening] = SlotOptions(longRunPossible: false, trackAvailable: false)
        let changed = availability.settingTrack(true, on: .monday)
        #expect(changed[.monday, .evening] == SlotOptions(longRunPossible: false, trackAvailable: true))
    }

    @Test("the choice is kept when parts are switched off, ignored while off, and holds when they return")
    func partsOffAndOn() {
        var availability = RunAvailability().togglingDay(.monday).settingTrack(true, on: .monday)
        availability = availability.togglingSlot(.morning, on: .monday).togglingSlot(.afternoon, on: .monday)
        #expect(availability.hasTrack(on: .monday))
        availability = availability.togglingSlot(.morning, on: .monday)
        #expect(availability[.monday, .morning].trackAvailable)

        // The last part off clears the day, which then has no track to show.
        let cleared = availability.togglingSlot(.morning, on: .monday).togglingSlot(.evening, on: .monday)
        #expect(!cleared.hasTrack(on: .monday))
    }

    @Test("availability stored without slot options has no track")
    func legacy() throws {
        let json = #"{"slots":{"2":["morning","evening"]}}"#
        let decoded = try JSONDecoder().decode(RunAvailability.self, from: Data(json.utf8))
        #expect(!decoded.hasTrack(on: .monday))
        #expect(decoded.settingTrack(true, on: .monday).hasTrack(on: .monday))
        #expect(decoded.settingTrack(true, on: .monday)[.monday] == [.morning, .evening])
    }

    @Test("the editor shows the switch at once and saves it")
    func editorSaves() async {
        let profile = RunAvailabilityEditorTests.Profile()
        let editor = makeEditor(profile)
        await editor.toggleDay(.thursday)

        await editor.setTrack(true, on: .thursday)

        #expect(editor.shown.hasTrack(on: .thursday))
        #expect(profile.availability.hasTrack(on: .thursday))
        #expect(!editor.didFail)
    }

    @Test("a failed save reverts the switch and reports it")
    func editorFailure() async {
        let profile = RunAvailabilityEditorTests.Profile()
        let editor = makeEditor(profile)
        await editor.toggleDay(.thursday)

        profile.failing = [2]
        await editor.setTrack(true, on: .thursday)

        #expect(editor.didFail)
        #expect(!editor.shown.hasTrack(on: .thursday))
        #expect(!profile.availability.hasTrack(on: .thursday))
    }

    @Test("the track choice round trips through the store")
    func persists() async throws {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture(timeZoneIdentifier: "UTC"))
        let viewModel = MicroCycleViewModel(model: model, refresher: FakeRefresher(), today: now)
        let availability = RunAvailability().togglingDay(.sunday).settingTrack(true, on: .sunday)

        #expect(await viewModel.setRunAvailability(availability, asOf: now))

        let stored = try #require(try await store.athleteProfile())
        #expect(stored.runAvailability == availability)
        #expect(stored.runAvailability.hasTrack(on: .sunday))
        #expect(viewModel.athleteViewModel.runAvailability.hasTrack(on: .sunday))
    }
}
