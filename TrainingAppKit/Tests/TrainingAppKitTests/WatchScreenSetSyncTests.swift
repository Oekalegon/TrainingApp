import Foundation
import Testing
import TrainingWatchKit
@testable import TrainingAppKit

@MainActor
private final class ScreenSender: WatchSyncSending {
    struct Failure: Error {}
    var screens: [RunScreenConfig] = []
    var failing = false
    var lastSendError: String?
    func send(zones: WatchZones) throws {}
    func send(plan: WatchPlan) throws {}
    func send(cues: CueSettings) throws {}
    func send(screens: RunScreenConfig) throws {
        if failing { throw Failure() }
        self.screens.append(screens)
    }
}

@MainActor
@Suite("WatchScreenSetSync (WATCH-134)")
struct WatchScreenSetSyncTests {
    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "WatchScreenSetSyncTests-\(UUID().uuidString)"))
    }

    private func set(_ id: String = "sprint", name: String = "Sprint", items: [RunScreenItem] = [.metric(.currentPace)]) -> RunScreenSet {
        RunScreenSet(id: id, name: name, screens: [RunScreen(id: "s", items: items)])
    }

    @Test("the screens start as the built-in ones, are sent once and again only when they change")
    func sendsChanges() throws {
        let sender = ScreenSender()
        let sync = WatchScreenSetSync(sender: sender, defaults: try defaults())
        #expect(sync.config == .default)
        sync.sync()
        sync.sync()
        #expect(sender.screens == [.default])
        try sync.save(set())
        #expect(sender.screens.count == 2)
        #expect(sender.screens.last?.sets.map(\.id) == ["sprint"])
    }

    @Test("a set is added, replaced by id and deleted, and what is kept survives a new launch")
    func saveReplaceDelete() throws {
        let defaults = try defaults()
        let sync = WatchScreenSetSync(sender: ScreenSender(), defaults: defaults)
        try sync.save(set())
        try sync.save(set(name: "Sprints"))
        try sync.save(set("long", name: "Long"))
        #expect(sync.config.sets.map(\.name) == ["Sprints", "Long"])
        #expect(WatchScreenSetSync(sender: ScreenSender(), defaults: defaults).config == sync.config)
        sync.deleteSet(id: "sprint")
        #expect(sync.config.sets.map(\.id) == ["long"])
    }

    @Test("a set that can't be used is refused and changes nothing")
    func validation() throws {
        let sender = ScreenSender()
        let sync = WatchScreenSetSync(sender: sender, defaults: try defaults())
        func fails(_ set: RunScreenSet, _ error: ScreenSetError) {
            #expect(throws: error) { try sync.save(set) }
        }
        fails(set(name: "  "), .emptyName)
        fails(RunScreenSet(id: "x", name: "X", screens: []), .noScreens)
        fails(set(items: []), .emptyScreen(id: "s"))
        fails(set(items: Array(repeating: .metric(.distance), count: 7)), .overCapacity(screenID: "s"))
        fails(set("default.workout"), .reservedID)
        let twice = RunScreenSet(id: "x", name: "X", screens: [
            RunScreen(id: "s", items: [.metric(.distance)]), RunScreen(id: "s", items: [.metric(.distance)])])
        fails(twice, .duplicateScreenID("s"))
        #expect(sync.config == .default)
        #expect(sender.screens.isEmpty)
    }

    @Test("the built-in sets keep their ids when their contents are edited")
    func editBuiltIns() throws {
        let sync = WatchScreenSetSync(sender: ScreenSender(), defaults: try defaults())
        try sync.updateFreeRun(set("anything", name: "Mine"))
        try sync.updateWorkout(set("other", name: "Workout mine"))
        #expect(sync.config.freeRun.id == RunScreenSet.freeRunDefault.id)
        #expect(sync.config.workout.id == RunScreenSet.workoutDefault.id)
        #expect(sync.config.freeRun.name == "Mine")
        #expect(throws: ScreenSetError.noScreens) { try sync.updateFreeRun(RunScreenSet(id: "x", name: "X", screens: [])) }
    }

    @Test("deleting a set or resetting removes the links to it; a link to a built-in template can be set and cleared")
    func links() throws {
        let defaults = try defaults()
        let links = WatchScreenLinks(defaults: defaults)
        let sync = WatchScreenSetSync(sender: ScreenSender(), defaults: defaults, links: links)
        let template = UUID()
        try sync.save(set())
        sync.link(builtInTemplate: template, to: "sprint")
        #expect(links.setID(forTemplate: template) == "sprint")
        sync.deleteSet(id: "sprint")
        #expect(links.setID(forTemplate: template) == nil)

        try sync.save(set("long", name: "Long"))
        sync.link(builtInTemplate: template, to: "long")
        sync.resetToDefaults()
        #expect(sync.config == .default)
        #expect(links.setID(forTemplate: template) == nil)
    }

    @Test("a failed send is reported and tried again at the next sync")
    func failedSend() throws {
        let sender = ScreenSender()
        sender.failing = true
        let sync = WatchScreenSetSync(sender: sender, defaults: try defaults())
        sync.sync()
        #expect(sync.lastError != nil)
        sender.failing = false
        sync.sync()
        #expect(sync.lastError == nil)
        #expect(sender.screens == [.default])
    }

    @Test("a new set has a fresh id and a standard screen that fits")
    func newSet() throws {
        let a = WatchScreenSetSync.newSet(named: "A"), b = WatchScreenSetSync.newSet(named: "B")
        #expect(a.id != b.id)
        try WatchScreenSetSync.validate(a)
    }
}
