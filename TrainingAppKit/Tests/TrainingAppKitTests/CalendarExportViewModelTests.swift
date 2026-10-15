import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("CalendarExportViewModel", .serialized)
struct CalendarExportViewModelTests {
    /// 2023-11-14 00:00 UTC, so `day(n)` is midnight UTC n days later.
    private func day(_ offset: Int, hour: Double = 0) -> Date {
        Date(timeIntervalSince1970: 1_699_920_000 + Double(offset) * 86400 + hour * 3600)
    }

    private func makeViewModel(failing: Bool = false) -> (InMemoryStore, CalendarExportViewModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: failing ? FailingWorkoutStore() : store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190))
        return (store, CalendarExportViewModel(model: model, today: day(0, hour: 9)))
    }

    @Test("the period starts as today through four weeks from today")
    func defaultPeriod() {
        let (_, viewModel) = makeViewModel()

        #expect(viewModel.firstDay == day(0))
        #expect(viewModel.lastDay == day(27))
        #expect(viewModel.isPeriodValid)
    }

    @Test("presets set the period")
    func presets() {
        let (_, viewModel) = makeViewModel()

        viewModel.apply(.lastTwelveWeeks)
        #expect(viewModel.firstDay == day(-83))
        #expect(viewModel.lastDay == day(0))

        viewModel.apply(.untilRace(name: "Marathon", date: day(120, hour: 9)))
        #expect(viewModel.firstDay == day(0))
        #expect(viewModel.lastDay == day(120))
    }

    @Test("the next primary race becomes an 'Until' preset; secondary races don't")
    func upcomingRacePreset() async throws {
        let (store, viewModel) = makeViewModel()
        try await store.upsert([
            Race(name: "10K", date: day(30), priority: .secondary),
            Race(name: "Marathon", date: day(120), priority: .primary),
            Race(name: "Old Marathon", date: day(-40), priority: .primary)
        ])

        await viewModel.loadUpcomingRace()

        #expect(viewModel.presets.first == .untilRace(name: "Marathon", date: day(120)))
        #expect(viewModel.presets.first?.title == "Until Marathon")
    }

    @Test("without an upcoming primary race only the fixed presets are offered")
    func noRacePreset() async {
        let (_, viewModel) = makeViewModel()

        await viewModel.loadUpcomingRace()

        #expect(viewModel.presets == [.nextFourWeeks, .lastTwelveWeeks])
    }

    @Test("exporting writes a JSON file covering the period, and changing the period discards it")
    func exportWritesFile() async throws {
        let (_, viewModel) = makeViewModel()
        viewModel.lastDay = day(6)

        await viewModel.export()

        let file = try #require(viewModel.exportedFile)
        #expect(file.pathExtension == "json")
        #expect(file.lastPathComponent.contains("2023-11-14 to 2023-11-20"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(CalendarExport.self, from: Data(contentsOf: file))
        #expect(export.days.count == 7)
        #expect(!viewModel.exportFailed)

        viewModel.lastDay = day(13)
        #expect(viewModel.exportedFile == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path), "a changed period deletes the old file")
    }

    @Test("a failing store gives a failure message, which a period change clears")
    func failedExport() async {
        let (_, viewModel) = makeViewModel(failing: true)

        await viewModel.export()

        #expect(viewModel.exportFailed)
        #expect(viewModel.exportedFile == nil)
        viewModel.lastDay = day(10)
        #expect(!viewModel.exportFailed)
    }

    @Test("discarding removes the written file")
    func discardRemovesFile() async throws {
        let (_, viewModel) = makeViewModel()
        viewModel.lastDay = day(2)
        await viewModel.export()
        let file = try #require(viewModel.exportedFile)

        viewModel.discardExportedFile()

        #expect(viewModel.exportedFile == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("a backwards period can't be exported")
    func backwardsPeriodRejected() async {
        let (_, viewModel) = makeViewModel()
        viewModel.lastDay = day(-3)

        await viewModel.export()

        #expect(!viewModel.isPeriodValid)
        #expect(viewModel.exportedFile == nil)
    }
}

/// A workout library whose reads fail, so exporting fails without a real storage error.
private struct FailingWorkoutStore: WorkoutLibraryStore {
    struct Failure: Error {}

    func workouts() async throws -> [StructuredWorkout] { throw Failure() }
    func workout(id: UUID) async throws -> StructuredWorkout? { nil }
    func upsert(_ workouts: [StructuredWorkout]) async throws {}
    func deleteWorkout(id: UUID) async throws {}
}
