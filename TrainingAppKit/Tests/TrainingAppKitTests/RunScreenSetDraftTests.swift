import Foundation
import Testing
import TrainingCore
import TrainingWatchKit
@testable import TrainingAppKit

@Suite("RunScreenSetDraft (WATCH-134)")
struct RunScreenSetDraftTests {
    private func draft() -> RunScreenSetDraft {
        RunScreenSetDraft(RunScreenSet(id: "x", name: "X", screens: [
            RunScreen(id: "a", items: [.metric(.distance)]), RunScreen(id: "b", items: [.metric(.heartRate)])]))
    }

    @Test("an item is added at the bottom while it fits, and refused when it doesn't")
    func adding() {
        var draft = draft()
        let zoneBar = draft.add(.widget(.zoneBar), to: "a")
        #expect(zoneBar)
        #expect(draft.screens[0].items == [.metric(.distance), .widget(.zoneBar)])
        #expect(draft.units(of: "a") == 3)
        // 3 + 2 + 1 = 6 fits, 7 doesn't.
        let histogram = draft.add(.widget(.zoneHistogram), to: "a")
        let time = draft.add(.metric(.totalTime), to: "a")
        #expect(histogram && time)
        #expect(draft.units(of: "a") == RunScreen.capacity)
        #expect(!draft.canAdd(.metric(.totalTime), to: "a"))
        let refused = draft.add(.metric(.totalTime), to: "a")
        #expect(!refused)
        #expect(draft.units(of: "a") == RunScreen.capacity)
        let unknown = draft.add(.metric(.totalTime), to: "missing")
        #expect(!unknown)
        #expect(draft.units(of: "missing") == 0)
    }

    @Test("items are removed and moved within their screen")
    func removingAndMoving() {
        var draft = draft()
        draft.add(.metric(.totalTime), to: "a")
        draft.add(.metric(.currentPace), to: "a")
        draft.moveItems(from: IndexSet(integer: 2), to: 0, in: "a")
        #expect(draft.screens[0].items == [.metric(.currentPace), .metric(.distance), .metric(.totalTime)])
        draft.removeItems(at: IndexSet(integer: 1), from: "a")
        #expect(draft.screens[0].items == [.metric(.currentPace), .metric(.totalTime)])
        #expect(draft.screens[1].items == [.metric(.heartRate)])
    }

    @Test("a screen is added with the total time on it, and the last screen can't be removed")
    func screens() {
        var draft = draft()
        let id = draft.addScreen()
        #expect(draft.screens.last?.id == id)
        #expect(draft.screens.last?.items == [.metric(.totalTime)])
        draft.removeScreens(at: IndexSet(0...2))
        #expect(draft.screens.count == 3)
        draft.removeScreens(at: IndexSet(0...1))
        #expect(draft.screens.map(\.id) == [id])
        draft.removeScreens(at: IndexSet(integer: 0))
        #expect(draft.screens.map(\.id) == [id])
    }

    @Test("a screen's name is shown only when it has one, and a name of spaces is none (WATCH-134)")
    func screenNames() {
        var draft = RunScreenSetDraft(RunScreenSet(
            id: "x", name: "X",
            screens: [RunScreen(id: "a", items: [.metric(.distance)]), RunScreen(id: "b", items: [.metric(.heartRate)], name: "  Hills ")]))
        #expect(draft.displayName(of: "a") == nil)
        #expect(draft.displayName(of: "b") == "Hills")
        draft.screens[0].name = "   "
        #expect(draft.displayName(of: "a") == nil)
        #expect(draft.set.screens.map(\.name) == [nil, "Hills"])
    }

    @Test("a screen's name survives encoding and a screen without one decodes as unnamed")
    func screenNameCoding() throws {
        let named = RunScreen(id: "a", items: [.metric(.distance)], name: "Easy")
        #expect(try JSONDecoder().decode(RunScreen.self, from: JSONEncoder().encode(named)).name == "Easy")
        let old = Data(#"{"id":"a","items":[]}"#.utf8)
        #expect(try JSONDecoder().decode(RunScreen.self, from: old).name == nil)
    }

    @Test("a screen added from a standard screen is named after it")
    func templateName() {
        var draft = RunScreenSetDraft(RunScreenSet(id: "x", name: "X", screens: [RunScreen(id: "a", items: [.metric(.distance)])]))
        let template = StandardScreens.all[0]
        let id = draft.addScreen(from: template)
        #expect(draft.displayName(of: id) == template.title)
    }

    @Test("the athlete's own screens are listed once, without the standard ones (WATCH-134)")
    func userScreens() {
        let mine = RunScreen(id: "m", items: [.metric(.distance), .metric(.currentPace)], name: "Hills")
        let copy = RunScreen(id: "other", items: mine.items, name: "Hills")
        let standard = RunScreen(id: "s", items: StandardScreens.all[0].items)
        let config = RunScreenConfig(
            freeRun: RunScreenSet(id: "f", name: "F", screens: [standard, mine]),
            workout: RunScreenSet(id: "w", name: "W", screens: [copy]),
            sets: [])
        #expect(ScreenLibrary.userScreens(in: config).map(\.id) == ["m"])
    }

    @Test("a search finds a screen by its name or by the name of any metric on it")
    func screenSearch() {
        let items: [RunScreenItem] = [.metric(.distance), .metric(.currentPace)]
        #expect(ScreenLibrary.matches(name: nil, items: items, query: "current pace"))
        #expect(ScreenLibrary.matches(name: nil, items: items, query: "  DISTANCE "))
        #expect(ScreenLibrary.matches(name: "Hill repeats", items: items, query: "hill"))
        #expect(!ScreenLibrary.matches(name: "Hill repeats", items: items, query: "cadence"))
        #expect(ScreenLibrary.matches(name: nil, items: items, query: ""))
        #expect(StandardScreens.all.contains { ScreenLibrary.matches(name: $0.title, items: $0.items, query: "current pace") })
    }

    @Test("adding a copy of an own screen gives it a new id and keeps its items and name")
    func addCopy() {
        var draft = RunScreenSetDraft(RunScreenSet(id: "x", name: "X", screens: [RunScreen(id: "a", items: [.metric(.distance)])]))
        let original = RunScreen(id: "m", items: [.metric(.heartRate)], name: "Zones")
        let id = draft.addScreen(copying: original)
        #expect(id != original.id)
        #expect(draft.screens.last?.items == original.items)
        #expect(draft.displayName(of: id) == "Zones")
    }

    @Test("a screen an older set opened on goes to the front, so the run still opens on it")
    func startsOnFirstScreen() {
        let set = RunScreenSet(
            id: "x", name: "X",
            screens: [RunScreen(id: "a", items: [.metric(.distance)]), RunScreen(id: "b", items: [.metric(.heartRate)])],
            startScreenID: "b")
        let draft = RunScreenSetDraft(set)
        #expect(draft.screens.map(\.id) == ["b", "a"])
        #expect(draft.startScreenID == nil)
        #expect(draft.set.startIndex == 0)
    }

    @Test("a screen is full for a watch when its items take all the units that watch fits")
    func fullScreen() {
        let draft = RunScreenSetDraft(RunScreenSet(
            id: "x", name: "X",
            screens: [RunScreen(id: "a", items: [.metric(.distance), .metric(.heartRate), .metric(.currentPace), .metric(.totalTime), .metric(.averagePace)])]))
        #expect(draft.isFull("a", fittingUnits: 5))
        #expect(!draft.isFull("a", fittingUnits: 6))
    }

    @Test("screens that come with the app are not the athlete's own, but a changed or named one is")
    func appScreensAreNotMine() {
        let easy = StandardScreens.all[0]
        let named = RunScreen(id: "a", items: easy.items, name: easy.title)
        let unnamedDefault = RunScreen(id: "b", items: RunScreenSet.workoutDefault.screens[0].items)
        let renamed = RunScreen(id: "c", items: easy.items, name: "My easy day")
        let changed = RunScreen(id: "d", items: easy.items + [.metric(.averagePace)])
        let blank = RunScreen(id: "e", items: [.metric(.totalTime)])
        let config = RunScreenConfig(
            freeRun: RunScreenSet(id: "f", name: "F", screens: [named, unnamedDefault, renamed, changed, blank]), workout: .workoutDefault, sets: [])
        #expect(ScreenLibrary.userScreens(in: config).map(\.id) == ["c", "d"])
    }

    @Test("a screen made in the set being edited is offered with the saved ones, once")
    func editingScreensAreOffered() {
        let mine = RunScreen(id: "m", items: [.metric(.distance), .metric(.currentPace)], name: "Hills")
        let config = RunScreenConfig(freeRun: RunScreenSet(id: "f", name: "F", screens: [mine]), workout: .workoutDefault, sets: [])
        let fresh = RunScreen(id: "n", items: [.metric(.heartRate)], name: "New")
        let screens = ScreenLibrary.userScreens(in: config, editing: [mine, fresh])
        #expect(screens.filter { $0.name == "Hills" }.count == 1)
        #expect(screens.contains { $0.id == "n" })
    }

    @Test("screens move, and a start screen that is deleted is forgotten so the run opens on the first")
    func startScreen() {
        var draft = draft()
        draft.startScreenID = "b"
        #expect(draft.startScreen?.id == "b")
        draft.moveScreens(from: IndexSet(integer: 1), to: 0)
        #expect(draft.screens.map(\.id) == ["b", "a"])
        draft.removeScreens(at: IndexSet(integer: 0))
        #expect(draft.startScreenID == nil)
        #expect(draft.startScreen?.id == "a")
    }

    @Test("the draft says why it can't be saved, and the built-in sets are not held to a name")
    func validation() {
        var draft = draft()
        #expect(draft.validationError() == nil)
        draft.name = " "
        #expect(draft.validationError() == .emptyName)
        #expect(draft.validationError(checksName: false) == nil)
        draft.name = "X"
        draft.removeItems(at: IndexSet(integer: 0), from: "a")
        #expect(draft.validationError() == .emptyScreen(id: "a"))
    }

    @Test("the draft turns back into the set it was made from")
    func roundTrip() {
        let set = RunScreenSet.workoutDefault
        #expect(RunScreenSetDraft(set).set == set)
    }
}

@Suite("RunScreenItemCatalogue (WATCH-134)")
struct RunScreenItemCatalogueTests {
    @Test("every metric and widget is in exactly one group")
    func complete() {
        let all = RunScreenItemCatalogue.groups.flatMap(\.items)
        // Every quantity but heart rate (whose run-wide latest, average and highest are older metrics) with every
        // statistic its scopes offer: the latest only for the run.
        let measured = RunQuantity.allCases.flatMap { quantity in
            RunScope.allCases.flatMap { scope in
                RunStatistic.allCases.filter(scope.offers).map { RunScreenItem.measure(quantity, $0, scope) }
            }
        }.filter { !RunScreenItemCatalogue.shownByMetrics.contains($0) }
        + RunSpanKind.allCases.flatMap { kind in [RunScope.step, .lastStep, .split, .lastSplit].map { RunScreenItem.span(kind, $0) } }
        let expected = RunMetric.allCases.map(RunScreenItem.metric) + RunWidget.allCases.map(RunScreenItem.widget) + measured
        #expect(Set(all) == Set(expected))
        #expect(all.count == expected.count)
        #expect(Set(all.map(\.title)).count == all.count)
    }

    @Test("the steps-only items are the ones a free run can't show")
    func stepsOnly() {
        let stepsOnly = RunScreenItemCatalogue.groups.flatMap(\.items).filter(\.requiresSteps)
        var expected: Set<RunScreenItem> = [
            .widget(.stepCountdown), .widget(.paceBar), .metric(.stepNumber), .metric(.stepTime), .metric(.stepDistance),
            .metric(.timeRemaining), .metric(.finishTime),
        ]
        for quantity in RunQuantity.allCases {
            for scope in [RunScope.step, .lastStep] {
                for statistic in RunStatistic.allCases where scope.offers(statistic) { expected.insert(.measure(quantity, statistic, scope)) }
            }
        }
        for kind in RunSpanKind.allCases { for scope in [RunScope.step, .lastStep] { expected.insert(.span(kind, scope)) } }
        #expect(Set(stepsOnly) == expected)
    }

    @Test("a search matches names and group names, ignoring case, and leaves no empty group")
    func search() {
        #expect(RunScreenItemCatalogue.groups(matching: "").count == RunScreenItemCatalogue.groups.count)
        #expect(RunScreenItemCatalogue.groups(matching: "pace").flatMap(\.items).prefix(2) == [.metric(.currentPace), .metric(.averagePace)])
        #expect(RunScreenItemCatalogue.groups(matching: "BATTERY").flatMap(\.items) == [.widget(.battery)])
        // A group's name matches all its items.
        #expect(RunScreenItemCatalogue.groups(matching: "heart rate").flatMap(\.items).count == 7 + 2 + 16)
        #expect(RunScreenItemCatalogue.groups(matching: "elevation").flatMap(\.items).prefix(3) == [.metric(.altitude), .metric(.elevationGain), .metric(.grade)])
        #expect(RunScreenItemCatalogue.groups(matching: "nothing like it").isEmpty)
    }
}

@Suite("Screens only in workouts (WATCH-135)")
struct ScreensOnlyInWorkoutsTests {
    @Test("a screen with an item for planned workouts is flagged, so the editor can say a free run leaves it out")
    func flagged() {
        var draft = RunScreenSetDraft(.workoutDefault)
        let id = draft.addScreen()
        #expect(!draft.isOnlyInWorkouts(id))
        let added = draft.add(.metric(.finishTime), to: id)
        #expect(added)
        #expect(draft.isOnlyInWorkouts(id))
        #expect(!draft.isOnlyInWorkouts("unknown"))
    }
}

@Suite("Catalogue sections (WATCH-135)")
struct CatalogueSectionsTests {
    @Test("a group is split by scope, the items with no scope first, and the parts hold every item once")
    func sections() throws {
        for group in RunScreenItemCatalogue.groups {
            #expect(group.sections.flatMap(\.items) == group.items.filter { $0.scope == nil } + RunScope.allCases.flatMap { scope in group.items.filter { $0.scope == scope } })
            #expect(Set(group.sections.flatMap(\.items)) == Set(group.items))
        }
        let heartRate = try #require(RunScreenItemCatalogue.groups.first { $0.title == "Heart Rate" })
        #expect(heartRate.sections.map(\.title) == [nil, "Whole Run", "This Step", "Last Step", "This Split", "Last Split"])
        let distance = try #require(RunScreenItemCatalogue.groups.first { $0.title == "Distance and Time" })
        #expect(distance.sections.first?.title == nil)
        #expect(distance.sections.map(\.title).contains("This Split"))
        #expect(distance.sections.map(\.title).contains("Last Step"))
    }
}

@Suite("StandardScreens (WATCH-137)")
struct StandardScreensTests {
    @Test("every standard screen has items, fits a screen and has a name of its own")
    func valid() {
        #expect(!StandardScreens.all.isEmpty)
        for template in StandardScreens.all {
            #expect(!template.items.isEmpty, "\(template.title) is empty")
            #expect(template.units <= RunScreen.capacity, "\(template.title) is too tall")
            #expect(RunScreen(id: template.id, items: template.items).fits)
            #expect(Set(template.items).count == template.items.count, "\(template.title) repeats an item")
        }
        #expect(Set(StandardScreens.all.map(\.id)).count == StandardScreens.all.count)
        #expect(Set(StandardScreens.all.map(\.title)).count == StandardScreens.all.count)
    }

    @Test("every item of a standard screen is one the editor's catalogue offers")
    func inCatalogue() {
        let offered = Set(RunScreenItemCatalogue.groups.flatMap(\.items))
        for template in StandardScreens.all {
            for item in template.items {
                // The whole-run latest, average and highest of heart rate and pace are the older metrics.
                #expect(offered.contains(item), "\(template.title): \(item.title) isn't in the catalogue")
            }
        }
    }

    @Test("the workout-only screens are the ones with a step item, and the rest run in a free run")
    func workoutOnly() {
        let only = StandardScreens.all.filter(\.isOnlyInWorkouts).map(\.id)
        #expect(only == ["intervals-heart-rate", "intervals-pace", "workout-progress"])
        #expect(StandardScreens.all.first { $0.id == "easy-run" }?.isOnlyInWorkouts == false)
    }

    @Test("adding a standard screen puts a copy of its items at the end, with a fresh id, and the draft stays valid")
    func adding() throws {
        var draft = RunScreenSetDraft(.freeRunDefault)
        let before = draft.screens.count
        let template = try #require(StandardScreens.all.first { $0.id == "splits" })
        let id = draft.addScreen(from: template)
        #expect(draft.screens.count == before + 1)
        #expect(draft.screens.last?.id == id)
        #expect(draft.screens.last?.items == template.items)
        #expect(draft.units(of: id) == template.units)
        let second = draft.addScreen(from: template)
        #expect(second != id)
        #expect(draft.validationError(checksName: false) == nil)
    }

    @Test("the summary lists the items and the units, and says when only planned workouts can show the screen")
    func summary() throws {
        let easy = try #require(StandardScreens.all.first { $0.id == "easy-run" })
        #expect(easy.summary == "Total Time, Distance, Current Pace, Heart Rate and Zone, Zone Bar. 6 of 6 units.")
        #expect(!easy.summary.contains("Planned workouts only"))
        let intervals = try #require(StandardScreens.all.first { $0.id == "intervals-pace" })
        #expect(intervals.summary.hasSuffix("Planned workouts only."))
        #expect(intervals.summary.contains("\(intervals.units) of \(RunScreen.capacity) units"))
    }
}

@Suite("Catalogue levels (WATCH-139)")
struct CatalogueLevelsTests {
    @Test("the first level opens only groups with more than two items; the small ones are listed as items, and nothing is lost")
    func levels() {
        let browsable = RunScreenItemCatalogue.browsableGroups
        #expect(browsable.allSatisfy { $0.items.count > RunScreenItemCatalogue.inlineLimit })
        #expect(Set(browsable.map(\.title)).count == browsable.count)
        // The battery is alone in its group, so it is an item of the first level.
        #expect(RunScreenItemCatalogue.inlineItems.contains(.widget(.battery)))
        let reachable = Set(browsable.flatMap(\.items)).union(RunScreenItemCatalogue.inlineItems)
        #expect(reachable == Set(RunScreenItemCatalogue.groups.flatMap(\.items)))
        // The first level is short: the groups and a few single items.
        #expect(browsable.count + RunScreenItemCatalogue.inlineItems.count <= 16)
    }

    @Test("a group's own view heads the items with no scope \"Metrics\", not the group's name, and the other parts by scope")
    func headers() throws {
        let heartRate = try #require(RunScreenItemCatalogue.groups.first { $0.title == "Heart Rate" })
        let titles = heartRate.sections.map(\.displayTitle)
        #expect(titles.first == "Metrics")
        #expect(!titles.contains("Heart Rate"))
        #expect(titles.contains("This Split"))
    }
}
