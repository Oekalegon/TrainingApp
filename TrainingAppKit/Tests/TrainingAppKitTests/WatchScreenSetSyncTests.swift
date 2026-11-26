import Foundation
import Testing
import TrainingCore
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

private struct BrokenTemplateStore: WorkoutTemplateStore {
    struct Failure: Error {}
    func templates() async throws -> [WorkoutTemplate] { [] }
    func template(id: UUID) async throws -> WorkoutTemplate? { nil }
    func upsert(_ templates: [WorkoutTemplate]) async throws { throw Failure() }
    func deleteTemplate(id: UUID) async throws {}
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

    @Test("a custom template is saved with the set, a built-in one is linked in the app, and the links are read back (WATCH-134)")
    func linkTemplates() async throws {
        let store = InMemoryStore()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        try await store.save(athlete)
        let model = TrainingModel(
            stores: StoreSet(
                activityStore: store, planStore: store, workoutStore: store, cycleStore: store,
                raceStore: store, athleteStore: store, templateStore: store),
            athlete: athlete)
        let defaults = try defaults()
        let sync = WatchScreenSetSync(sender: ScreenSender(), defaults: defaults, links: WatchScreenLinks(defaults: defaults))
        let custom = WorkoutTemplate(name: "Mine", sport: .running, parameters: [], blocks: [])
        let builtIn = BuiltInWorkoutTemplates.easyRun

        try await sync.link(custom, isCustom: true, to: "sprint", model: model)
        let saved = try #require(try await store.template(id: custom.id))
        #expect(saved.watchScreenSetID == "sprint")
        #expect(sync.linkedSetID(for: saved, isCustom: true) == "sprint")

        try await sync.link(builtIn, isCustom: false, to: "sprint", model: model)
        #expect(sync.linkedSetID(for: builtIn, isCustom: false) == "sprint")
        #expect(try await store.template(id: builtIn.id) == nil)

        try await sync.link(builtIn, isCustom: false, to: nil, model: model)
        #expect(sync.linkedSetID(for: builtIn, isCustom: false) == nil)
    }

    private func model(templates: (any WorkoutTemplateStore)?, store: InMemoryStore) async throws -> TrainingModel {
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        try await store.save(athlete)
        return TrainingModel(
            stores: StoreSet(
                activityStore: store, planStore: store, workoutStore: store, cycleStore: store,
                raceStore: store, athleteStore: store, templateStore: templates),
            athlete: athlete)
    }

    @Test("linking an existing custom template changes only its screen set, and moves it from one set to another (WATCH-134)")
    func linkExistingTemplate() async throws {
        let store = InMemoryStore()
        let model = try await model(templates: store, store: store)
        let defaults = try defaults()
        let sync = WatchScreenSetSync(sender: ScreenSender(), defaults: defaults, links: WatchScreenLinks(defaults: defaults))
        let template = BuiltInWorkoutTemplates.easyRun
        var custom = WorkoutTemplate(
            name: "Mine", sport: template.sport, venue: template.venue, parameters: template.parameters,
            blocks: template.blocks, sessionType: .long)
        try await store.upsert([custom])

        try await sync.link(custom, isCustom: true, to: "a", model: model)
        custom.watchScreenSetID = "a"
        #expect(try await store.template(id: custom.id) == custom)
        try await sync.link(custom, isCustom: true, to: "b", model: model)
        custom.watchScreenSetID = "b"
        #expect(try await store.template(id: custom.id) == custom)
        #expect(try await store.templates().count == 1)
    }

    @Test("a template store that fails, or none, makes the link throw and changes nothing")
    func linkFailures() async throws {
        let defaults = try defaults()
        let sync = WatchScreenSetSync(sender: ScreenSender(), defaults: defaults, links: WatchScreenLinks(defaults: defaults))
        let custom = WorkoutTemplate(name: "Mine", sport: .running, parameters: [], blocks: [])
        for templates in [BrokenTemplateStore() as any WorkoutTemplateStore, nil] {
            let model = try await model(templates: templates, store: InMemoryStore())
            await #expect(throws: (any Error).self) {
                try await sync.link(custom, isCustom: true, to: "a", model: model)
            }
        }
        #expect(sync.linkedSetID(for: custom, isCustom: true) == nil)
    }

    @Test("every reason a set can't be saved has words for the athlete")
    func messages() {
        let errors: [ScreenSetError] = [
            .emptyName, .noScreens, .emptyScreen(id: "a"), .overCapacity(screenID: "a"), .duplicateScreenID("a"), .reservedID,
        ]
        #expect(errors.allSatisfy { !$0.userMessage.isEmpty })
        #expect(Set(errors.map(\.userMessage)).count == errors.count)
    }
}
