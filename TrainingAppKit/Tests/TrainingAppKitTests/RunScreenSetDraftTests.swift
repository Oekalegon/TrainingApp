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
