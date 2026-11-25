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
        #expect(RunScreenSet.freeRunDefault.screens.first?.items == RunMetric.allCases.map(RunScreenItem.metric))
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
        #expect(store.set(forWorkout: true) == custom.workout)
        #expect(store.set(forWorkout: false) == custom.freeRun)
    }
}
