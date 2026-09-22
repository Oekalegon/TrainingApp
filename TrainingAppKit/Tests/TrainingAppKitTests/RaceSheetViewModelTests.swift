import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("RaceSheetViewModel")
struct RaceSheetViewModelTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .init(identifier: "UTC")!
        return calendar
    }

    private func makeModel() async -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        return (store, TrainingModel(stores: stores, athlete: athlete))
    }

    @Test("canSave is false with a blank name, true once a name is entered")
    func canSaveTracksName() async {
        let (_, model) = await makeModel()
        let viewModel = RaceSheetViewModel(model: model, date: day(0))

        #expect(!viewModel.canSave)

        viewModel.name = "Local 10K"
        #expect(viewModel.canSave)

        viewModel.name = "   "
        #expect(!viewModel.canSave)
    }

    @Test("save() persists a race with the entered name/date/priority, trimmed and date normalized to start of day")
    func saveCreatesRace() async {
        let (store, model) = await makeModel()
        let viewModel = RaceSheetViewModel(model: model, date: day(0))
        viewModel.name = "  Local 10K  "
        viewModel.date = day(30)
        viewModel.priority = .secondary

        let saved = await viewModel.save()

        #expect(saved)
        let races = model.races
        #expect(races.count == 1)
        #expect(races.first?.name == "Local 10K")
        // Normalized, not the raw `day(30)` — see `save()`'s own doc comment on why
        // `PlanEvaluator`'s race-day TSB rule needs this to be an exact start-of-day value.
        #expect(races.first?.date == utcCalendar.startOfDay(for: day(30)))
        #expect(races.first?.priority == .secondary)
        let stored = try? await store.races(in: day(0)...day(60))
        #expect(stored?.first?.name == "Local 10K")
    }

    @Test("save() with a blank name is a no-op, saving nothing")
    func saveWithBlankNameIsNoOp() async {
        let (_, model) = await makeModel()
        let viewModel = RaceSheetViewModel(model: model, date: day(0))
        viewModel.name = "   "

        let saved = await viewModel.save()

        #expect(!saved)
        #expect(model.races.isEmpty)
    }

    @Test("minimumDate(asOf:) is today's start of day in the athlete's timezone")
    func minimumDateIsTodayStartOfDay() async {
        let (_, model) = await makeModel()
        let viewModel = RaceSheetViewModel(model: model, date: day(0))

        let today = day(5)
        #expect(viewModel.minimumDate(asOf: today) == utcCalendar.startOfDay(for: today))
    }

    @Test("save() sets saveError and returns false when the store fails, without touching model.races")
    func saveReportsStoreFailure() async {
        let store = InMemoryStore()
        let failingStores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: FailingRaceStore(), athleteStore: store
        )
        let model = TrainingModel(stores: failingStores, athlete: AthleteProfile.fixture(timeZoneIdentifier: "UTC"))
        let viewModel = RaceSheetViewModel(model: model, date: day(0))
        viewModel.name = "Local 10K"

        let saved = await viewModel.save()

        #expect(!saved)
        #expect(viewModel.saveError != nil)
        #expect(model.races.isEmpty)
    }

    @Test("a second concurrent save() call is a no-op while the first is still in flight")
    func concurrentSaveCallsDoNotDoubleSave() async {
        let (_, model) = await makeModel()
        let viewModel = RaceSheetViewModel(model: model, date: day(0))
        viewModel.name = "Local 10K"

        async let first = viewModel.save()
        async let second = viewModel.save()
        let (firstResult, secondResult) = await (first, second)

        // Exactly one of the two actually saved -- both racing to `true` (or both silently
        // dropping to `false`) would either double-persist or silently lose the save.
        #expect(firstResult != secondResult)
        #expect(model.races.count == 1)
    }
}

/// A `RaceStore` whose `upsert` always throws, for exercising `RaceSheetViewModel.save()`'s error
/// path without a real storage failure. Every other method is unused by that path, so each just
/// returns an empty/`nil` result.
private struct FailingRaceStore: RaceStore {
    struct Failure: Error {}

    func races(in range: ClosedRange<Date>) async throws -> [Race] { [] }
    func race(id: UUID) async throws -> Race? { nil }
    func upsert(_ races: [Race]) async throws { throw Failure() }
    func deleteRace(id: UUID) async throws {}
}
