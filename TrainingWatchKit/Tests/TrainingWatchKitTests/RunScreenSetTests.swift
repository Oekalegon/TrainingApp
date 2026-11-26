import Foundation
import Testing
@testable import TrainingWatchKit

@Suite("Run screen sets (WATCH-109)")
struct RunScreenSetTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("a set survives encoding and decoding")
    func roundTrip() throws {
        let config = RunScreenConfig(
            freeRun: RunScreenSet(id: "a", name: "A", screens: [RunScreen(id: "s", items: [.metric(.distance), .metric(.heartRate)])], startScreenID: "s"),
            workout: .workoutDefault)
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(RunScreenConfig.self, from: data) == config)
    }

    @Test("an unknown metric or item kind is dropped, the rest stays")
    func unknownItems() throws {
        let screen = try decode(RunScreen.self, """
        {"id":"s","items":[{"kind":"metric","id":"distance"},{"kind":"metric","id":"vo2"},{"kind":"widget","id":"x"},{"kind":"metric","id":"heartRate"}]}
        """)
        #expect(screen.items == [.metric(.distance), .metric(.heartRate)])
    }

    @Test("items past the capacity are cut from the top")
    func capacity() throws {
        let items = (0..<8).map { _ in #"{"kind":"metric","id":"distance"}"# }.joined(separator: ",")
        let screen = try decode(RunScreen.self, #"{"id":"s","items":[\#(items)]}"#)
        #expect(screen.units == RunScreen.capacity)
        #expect(screen.fits)
        #expect(RunScreen.fitted([.metric(.totalTime)] + Array(repeating: .metric(.distance), count: 6)).first == .metric(.distance))
    }

    @Test("empty screens are dropped, and an unusable set falls back to the default")
    func fallback() throws {
        let set = try decode(RunScreenSet.self, #"{"id":"a","name":"A","screens":[{"id":"s","items":[{"kind":"widget","id":"x"}]}]}"#)
        #expect(set.screens.isEmpty)
        let config = try decode(RunScreenConfig.self, #"{"freeRun":{"id":"a","name":"A","screens":[]},"workout":"junk"}"#)
        #expect(config == .default)
    }

    @Test("the start screen is found by id, and the first one when unknown")
    func start() {
        let screens = [RunScreen(id: "a", items: [.metric(.distance)]), RunScreen(id: "b", items: [.metric(.heartRate)])]
        #expect(RunScreenSet(id: "x", name: "X", screens: screens, startScreenID: "b").startIndex == 1)
        #expect(RunScreenSet(id: "x", name: "X", screens: screens, startScreenID: "zz").startIndex == 0)
        #expect(RunScreenSet(id: "x", name: "X", screens: screens).startIndex == 0)
    }

    @Test("the default reproduces today's standard screen")
    func defaults() {
        #expect(RunScreenSet.freeRunDefault.screens.first?.items == RunMetric.standard.map(RunScreenItem.metric))
    }

    @Test("the screens travel in the context, and a context without them still decodes")
    func inContext() throws {
        let context = WatchContext(screens: .default)
        #expect(WatchContext(data: try JSONEncoder().encode(context))?.screens == .default)
        #expect(try decode(WatchContext.self, "{}").screens == nil)
        #expect(try decode(WatchContext.self, #"{"screens":"junk"}"#).screens == nil)
    }

    @Test("the store keeps what it is given for the next launch")
    @MainActor
    func store() throws {
        let defaults = try #require(UserDefaults(suiteName: "RunScreenSetTests.\(UUID())"))
        let store = RunScreenStore(cache: RunScreenCache(defaults: defaults))
        #expect(store.config == .default)
        var custom = RunScreenConfig.default
        custom.workout = RunScreenSet(id: "w", name: "W", screens: [RunScreen(id: "s", items: [.metric(.heartRate)])])
        store.update(custom)
        #expect(RunScreenStore(cache: RunScreenCache(defaults: defaults)).config == custom)
        #expect(store.set(for: WatchPlannedWorkout(id: UUID(), date: .now, name: "W", blocks: [])) == custom.workout)
        #expect(store.set(for: nil) == custom.freeRun)
    }

    @Test("a repeated screen id keeps the first screen")
    func duplicateIDs() throws {
        let set = try decode(RunScreenSet.self, """
        {"id":"a","name":"A","screens":[
        {"id":"s","items":[{"kind":"metric","id":"distance"}]},
        {"id":"s","items":[{"kind":"metric","id":"heartRate"}]},
        {"id":"t","items":[{"kind":"metric","id":"totalTime"}]}]}
        """)
        #expect(set.screens.map(\.id) == ["s", "t"])
        #expect(set.screens.first?.items == [.metric(.distance)])
    }

    @Test("the selection opens on the start screen, and the screens of steps are left out of a run with none")
    func selectionOpening() {
        let set = RunScreenSet.workoutDefault
        #expect(RunScreenSelection(set: set, hasSteps: true).current == "dial")
        // The steps arrive a moment after the run starts: until then the dial can't show.
        var selection = RunScreenSelection(set: set, hasSteps: false)
        #expect(selection.current == "standard")
        #expect(selection.screens(hasSteps: false).map(\.id) == ["standard"])
        selection.stepsChanged(hasSteps: true)
        #expect(selection.current == "dial")
        selection.stepsChanged(hasSteps: false)
        #expect(selection.current == "standard")

        let free = RunScreenSelection(set: .freeRunDefault, hasSteps: false)
        #expect(free.current == "standard")
    }

    @Test("a screen the athlete turned to stays when the steps start, but one that needs the steps goes when they are used up")
    func selectionKeepsTheAthletesScreen() {
        var selection = RunScreenSelection(set: .workoutDefault, hasSteps: true)
        selection.select("standard")
        selection.stepsChanged(hasSteps: true)
        #expect(selection.current == "standard")
        selection.stepsChanged(hasSteps: false)
        #expect(selection.current == "standard")

        var onDial = RunScreenSelection(set: .workoutDefault, hasSteps: true)
        onDial.stepsChanged(hasSteps: false)
        #expect(onDial.current == "standard")
    }

    @Test("a set with a start screen that does not exist opens on the first screen")
    func selectionUnknownStart() {
        let set = RunScreenSet(id: "x", name: "X", screens: [RunScreen(id: "a", items: [.metric(.distance)])], startScreenID: "zz")
        #expect(RunScreenSelection(set: set, hasSteps: false).current == "a")
    }

    @Test("widgets travel with their id, an unknown one is dropped, and they have heights")
    func widgets() throws {
        let screen = try decode(RunScreen.self, """
        {"id":"s","items":[{"kind":"widget","id":"zoneBar"},{"kind":"widget","id":"hologram"},{"kind":"widget","id":"battery"}]}
        """)
        #expect(screen.items == [.widget(.zoneBar), .widget(.battery)])
        #expect(screen.units == 3)
        let data = try JSONEncoder().encode(screen)
        #expect(try JSONDecoder().decode(RunScreen.self, from: data) == screen)
        #expect(RunScreen(id: "d", items: [.widget(.stepCountdown)]).requiresSteps)
        #expect(!RunScreen(id: "d", items: [.widget(.zoneBar), .metric(.distance)]).requiresSteps)
    }

    @Test("the workout default holds the dial in six units and opens on it")
    func workoutDefault() throws {
        let dial = try #require(RunScreenSet.workoutDefault.screens.first { $0.id == "dial" })
        #expect(dial.units == RunScreen.capacity)
        #expect(RunScreenSet.workoutDefault.startIndex == 1)
    }

    @Test("a screen too tall for a small watch loses its first items and keeps the last")
    func fitting() {
        let screen = RunScreen(id: "d", items: [.widget(.stepCountdown), .metric(.heartRate), .widget(.zoneBar), .metric(.totalTime), .widget(.battery)])
        #expect(screen.items(fittingUnits: 6) == screen.items)
        #expect(screen.items(fittingUnits: 5) == Array(screen.items.dropFirst()))
        #expect(screen.items(fittingUnits: 3) == [.metric(.totalTime), .widget(.battery)])
        #expect(screen.items(fittingUnits: 0) == [.widget(.battery)])
    }

    private func plan(setID: String?) -> WatchPlannedWorkout {
        WatchPlannedWorkout(id: UUID(), date: .now, name: "W", blocks: [], screenSetID: setID)
    }

    @MainActor
    @Test("a workout runs with the set it names, and with the workout default when it names none or one the watch lacks (WATCH-133)")
    func setForWorkout() {
        let sprint = RunScreenSet(id: "sprint", name: "Sprint", screens: [RunScreen(id: "s", items: [.metric(.currentPace)])])
        let config = RunScreenConfig(sets: [sprint])
        #expect(config.set(withID: "sprint") == sprint)
        #expect(config.set(withID: nil) == config.workout)
        #expect(config.set(withID: "gone") == config.workout)
        let defaults = UserDefaults(suiteName: "RunScreenSetTests.\(UUID())")!
        let cache = RunScreenCache(defaults: defaults)
        cache.save(config)
        let store = RunScreenStore(cache: cache)
        #expect(store.set(for: plan(setID: "sprint")) == sprint)
        #expect(store.set(for: plan(setID: "gone")) == config.workout)
        #expect(store.set(for: nil) == config.freeRun)
    }

    @Test("the sets decode leniently: an unreadable, empty or repeated one is left out")
    func setsDecoding() throws {
        let config = try decode(RunScreenConfig.self, """
        {"sets":[
        {"id":"a","name":"A","screens":[{"id":"s","items":[{"kind":"metric","id":"distance"}]}]},
        {"id":"a","name":"Again","screens":[{"id":"s","items":[{"kind":"metric","id":"distance"}]}]},
        {"id":"b","name":"B","screens":[]},
        "junk"]}
        """)
        #expect(config.sets.map(\.id) == ["a"])
        #expect(config.sets.first?.name == "A")
        // A config from before sets existed still decodes.
        #expect(try decode(RunScreenConfig.self, "{}").sets.isEmpty)
    }

    @Test("the screen set of a workout travels in the plan, and a plan without it still decodes")
    func planCarriesTheSet() throws {
        let workout = plan(setID: "sprint")
        let data = try JSONEncoder().encode(workout)
        #expect(try JSONDecoder().decode(WatchPlannedWorkout.self, from: data).screenSetID == "sprint")
        let old = try JSONEncoder().encode(plan(setID: nil))
        #expect(try JSONDecoder().decode(WatchPlannedWorkout.self, from: old).screenSetID == nil)
    }
}

@Suite("RunScreenPage fitting units (WATCH-138)")
struct RunScreenPageFittingTests {
    @Test("the large watches fit 6 units, a 41 mm watch 5, and no screen fewer than 3")
    func fitting() {
        #expect(RunScreenPage.fittingUnits(forScreenHeight: 251) == 6)
        #expect(RunScreenPage.fittingUnits(forScreenHeight: 242) == 6)
        #expect(RunScreenPage.fittingUnits(forScreenHeight: 215) == 5)
        #expect(RunScreenPage.fittingUnits(forScreenHeight: 100) == 3)
        #expect(RunScreenPage.fittingUnits(forScreenHeight: 1000) == RunScreen.capacity)
    }
}
