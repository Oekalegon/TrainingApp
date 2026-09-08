import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("WeekViewModel")
struct WeekViewModelTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeStores() -> (InMemoryStore, StoreSet) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
        return (store, stores)
    }

    private func makeModel(weekStartsOn: Weekday = .monday) -> TrainingModel {
        let (_, stores) = makeStores()
        let athlete = AthleteProfile.fixture(weekStartsOn: weekStartsOn, timeZoneIdentifier: "UTC")
        return TrainingModel(stores: stores, athlete: athlete)
    }

    @Test("displayedWeekStart lands on the athlete's week-start day, not just any day")
    func displayedWeekStartRespectsWeekStartsOn() {
        let model = makeModel(weekStartsOn: .monday)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(3))

        let calendar = WeekViewModel.calendar(for: model.athlete)
        #expect(calendar.component(.weekday, from: viewModel.displayedWeekStart) == Weekday.monday.rawValue)
    }

    @Test("weekDates has exactly the 7 days starting at displayedWeekStart")
    func weekDatesIsSevenConsecutiveDays() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        #expect(viewModel.weekDates.count == 7)
        #expect(viewModel.weekDates.first == viewModel.displayedWeekStart)
    }

    @Test("weekDates(offsetWeeks:) returns the neighboring weeks without moving displayedWeekStart")
    func weekDatesWithOffsetReflectsNeighboringWeeksOnly() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: model.athlete)
        let originalStart = viewModel.displayedWeekStart

        let previous = viewModel.weekDates(offsetWeeks: -1)
        let next = viewModel.weekDates(offsetWeeks: 1)

        #expect(previous.count == 7)
        #expect(next.count == 7)
        #expect(previous.first == calendar.date(byAdding: .day, value: -7, to: originalStart))
        #expect(next.first == calendar.date(byAdding: .day, value: 7, to: originalStart))
        // Neither call should have moved the actual navigation state.
        #expect(viewModel.displayedWeekStart == originalStart)
    }

    @Test("chartRange spans the week before, the displayed week, and the week after")
    func chartRangeIsThreeWeeksCenteredOnDisplayedWeek() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: model.athlete)

        let expectedStart = calendar.date(byAdding: .day, value: -7, to: viewModel.displayedWeekStart)!
        let expectedEnd = calendar.date(byAdding: .day, value: 13, to: viewModel.displayedWeekStart)!

        #expect(viewModel.chartRange.lowerBound == expectedStart)
        #expect(viewModel.chartRange.upperBound == expectedEnd)
        // 3 weeks = 21 days inclusive of both ends.
        let dayCount = calendar.dateComponents([.day], from: expectedStart, to: expectedEnd).day!
        #expect(dayCount == 20)
    }

    @Test("goToNextWeek/goToPreviousWeek move by exactly 7 days")
    func weekNavigationMovesBySevenDays() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let start = viewModel.displayedWeekStart
        let calendar = WeekViewModel.calendar(for: model.athlete)

        viewModel.goToNextWeek()
        #expect(viewModel.displayedWeekStart == calendar.date(byAdding: .day, value: 7, to: start))

        viewModel.goToPreviousWeek()
        viewModel.goToPreviousWeek()
        #expect(viewModel.displayedWeekStart == calendar.date(byAdding: .day, value: -7, to: start))
    }

    @Test("goToToday returns to the week containing the given date after navigating away")
    func goToTodayReturnsToCurrentWeek() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let start = viewModel.displayedWeekStart

        viewModel.goToNextWeek()
        viewModel.goToNextWeek()
        #expect(viewModel.displayedWeekStart != start)

        viewModel.goToToday(asOf: day(0))
        #expect(viewModel.displayedWeekStart == start)
    }

    @Test("activities(on:) and plans(on:) filter to exactly that calendar day")
    func activitiesAndPlansFilterByDay() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let workout = StructuredWorkout(
            name: "Steady", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
        let onDay = Activity(source: .manual, sport: .running, start: day(2), duration: 1800)
        let otherDay = Activity(source: .manual, sport: .cycling, start: day(3), duration: 1800)
        let plan = PlannedActivity(workoutID: workout.id, date: day(2))
        try await store.upsert([workout])
        try await store.upsert([onDay, otherDay])
        try await store.upsert([plan])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(6), asOf: day(2))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        #expect(viewModel.activities(on: day(2)).map(\.id) == [onDay.id])
        #expect(viewModel.activities(on: day(3)).map(\.id) == [otherDay.id])
        #expect(viewModel.plans(on: day(2)).map(\.id) == [plan.id])
        #expect(viewModel.plans(on: day(3)).isEmpty)
        #expect(viewModel.workout(for: plan)?.id == workout.id)
    }

    @Test("activityDetailViewModel(for:) wires the model's athlete through")
    func activityDetailViewModelUsesModelAthlete() {
        let (_, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "Europe/Amsterdam")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let activity = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)

        let detail = viewModel.activityDetailViewModel(for: activity)

        #expect(detail.activity.id == activity.id)
        #expect(detail.timeZone.identifier == "Europe/Amsterdam")
    }

    @Test("athleteViewModel wires the model's athlete through")
    func athleteViewModelUsesModelAthlete() {
        let (_, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "Europe/Amsterdam")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        #expect(viewModel.athleteViewModel.athlete.timeZone.identifier == "Europe/Amsterdam")
    }

    @Test("load(asOf:) loads chartRange (3 weeks), not just the displayed week")
    func loadFetchesChartRangeIntoModel() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        // Inside chartRange (the week after the displayed one) but outside weekDates — proves
        // `load` fetches the wider 3-week window, not just the 7 displayed days.
        let calendar = WeekViewModel.calendar(for: athlete)
        let nextWeekDay = calendar.date(byAdding: .day, value: 10, to: viewModel.displayedWeekStart)!
        let activity = Activity(source: .manual, sport: .running, start: nextWeekDay, duration: 1800)
        try await store.upsert([activity])
        #expect(model.activities.isEmpty)

        await viewModel.load(asOf: day(0))

        #expect(model.activities.map(\.id) == [activity.id])
    }

    @Test("hasNoActivities reflects whether an import has ever happened, for the empty-state prompt")
    func hasNoActivitiesReflectsModelState() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        #expect(viewModel.hasNoActivities)

        try await store.saveImportAnchor(ImportAnchor(data: Data([1])))
        try await model.load(in: day(0)...day(6), asOf: day(0))

        #expect(!viewModel.hasNoActivities)
    }

    @Test("hasNoActivities stays false once imported, even if the current chart range has no activities")
    func hasNoActivitiesIgnoresCurrentlyLoadedRange() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        // An activity months outside the loaded chart range -- proves hasNoActivities doesn't
        // flip back on just because the displayed week's window happens to be empty.
        let outOfRange = Activity(source: .healthKit(UUID()), sport: .running, start: day(200), duration: 1800)
        try await store.upsert([outOfRange])
        try await store.saveImportAnchor(ImportAnchor(data: Data([1])))

        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        await viewModel.load(asOf: day(0))

        #expect(model.activities.isEmpty)
        #expect(!viewModel.hasNoActivities)
    }

    @Test("refresh(asOf:) toggles isRefreshing and delegates to the refresher")
    func refreshDelegatesAndTogglesFlag() async {
        let model = makeModel()
        let refresher = FakeRefresher()
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))

        #expect(!viewModel.isRefreshing)
        await viewModel.refresh(asOf: day(0))
        #expect(!viewModel.isRefreshing)
        #expect(refresher.callCount == 1)
    }

    @Test("refresh(asOf:) clears isRefreshing even when the refresher throws")
    func refreshClearsFlagOnFailure() async {
        let model = makeModel()
        let refresher = FakeRefresher(shouldThrow: true)
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))

        await viewModel.refresh(asOf: day(0))
        #expect(!viewModel.isRefreshing)
    }

    @Test("resyncActivities(asOf:) toggles isResyncing and delegates to the refresher")
    func resyncDelegatesAndTogglesFlag() async {
        let model = makeModel()
        let refresher = FakeRefresher()
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))

        #expect(!viewModel.isResyncing)
        await viewModel.resyncActivities(asOf: day(0))
        #expect(!viewModel.isResyncing)
        #expect(refresher.resyncCallCount == 1)
    }

    @Test("resyncActivities(asOf:) clears isResyncing even when the refresher throws")
    func resyncClearsFlagOnFailure() async {
        let model = makeModel()
        let refresher = FakeRefresher(shouldThrow: true)
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))

        await viewModel.resyncActivities(asOf: day(0))
        #expect(!viewModel.isResyncing)
    }

    @Test("resyncActivities(asOf:) doesn't affect isRefreshing, and vice versa")
    func resyncAndRefreshFlagsAreIndependent() async {
        let model = makeModel()
        let refresher = FakeRefresher()
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))

        await viewModel.resyncActivities(asOf: day(0))
        #expect(!viewModel.isRefreshing)

        await viewModel.refresh(asOf: day(0))
        #expect(!viewModel.isResyncing)
    }

    @Test("resyncActivities(asOf:) reaches TrainingModel end-to-end, same as refresh(asOf:) does")
    func resyncActivitiesUpdatesModelEndToEnd() async throws {
        let model = makeModel()
        let refresher = ModelBackedFakeRefresher(model: model)
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))
        #expect(viewModel.hasNoActivities)

        await viewModel.resyncActivities(asOf: day(0))

        #expect(!viewModel.hasNoActivities)
    }

    @Test("connectHealthData(asOf:) requests authorization before refreshing")
    func connectHealthDataRequestsAuthorizationThenRefreshes() async {
        let model = makeModel()
        let refresher = FakeRefresher()
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))

        await viewModel.connectHealthData(asOf: day(0))

        #expect(refresher.authorizationRequested)
        #expect(refresher.callCount == 1)
        #expect(!viewModel.isRefreshing)
    }

    @Test("connectHealthData(asOf:) skips the import if authorization fails")
    func connectHealthDataSkipsRefreshOnAuthorizationFailure() async {
        let model = makeModel()
        let refresher = FakeRefresher(shouldThrow: true)
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))

        await viewModel.connectHealthData(asOf: day(0))

        #expect(refresher.authorizationRequested)
        #expect(refresher.callCount == 0)
        #expect(!viewModel.isRefreshing)
    }

    @Test("connectHealthData(asOf:) clears hasNoActivities once the import completes")
    func connectHealthDataClearsEmptyState() async throws {
        let model = makeModel()
        let refresher = ModelBackedFakeRefresher(model: model)
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))
        #expect(viewModel.hasNoActivities)

        await viewModel.connectHealthData(asOf: day(0))

        #expect(!viewModel.hasNoActivities)
    }
}

@MainActor
private final class FakeRefresher: ActivityRefreshing {
    private(set) var callCount = 0
    private(set) var authorizationRequested = false
    private let shouldThrow: Bool

    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    struct Boom: Error {}

    private(set) var resyncCallCount = 0

    func refreshActivities(asOf today: Date) async throws {
        callCount += 1
        if shouldThrow { throw Boom() }
    }

    func resyncActivities(asOf today: Date) async throws {
        resyncCallCount += 1
        if shouldThrow { throw Boom() }
    }

    func requestAuthorization() async throws {
        authorizationRequested = true
        if shouldThrow { throw Boom() }
    }
}

/// Unlike `FakeRefresher`, which just counts calls, this actually drives `model.importActivities(from:)`
/// with a stub `ActivityImporting` — so a test can assert the real end-to-end effect of a refresh/
/// connect on `model` (and therefore on anything, like `WeekViewModel.hasNoActivities`, that's
/// derived from it), the way the app's real `TrainingAppEnvironment` does.
@MainActor
private final class ModelBackedFakeRefresher: ActivityRefreshing {
    private let model: TrainingModel

    init(model: TrainingModel) {
        self.model = model
    }

    func refreshActivities(asOf today: Date) async throws {
        try await model.importActivities(from: StubImporter(), asOf: today)
    }

    func resyncActivities(asOf today: Date) async throws {
        try await model.resyncActivities(from: StubImporter(), asOf: today)
    }

    func requestAuthorization() async throws {}
}

private struct StubImporter: ActivityImporting {
    func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
        ImportResult(upserted: [], deletedSources: [], anchor: ImportAnchor(data: Data([1])))
    }
}
