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
}
