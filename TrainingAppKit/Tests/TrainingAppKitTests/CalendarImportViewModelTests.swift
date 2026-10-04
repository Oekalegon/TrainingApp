import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("CalendarImportViewModel", .serialized)
struct CalendarImportViewModelTests {
    /// 2023-11-14 00:00 UTC, so `day(n)` is midnight UTC n days later.
    private func day(_ offset: Int, hour: Double = 0) -> Date {
        Date(timeIntervalSince1970: 1_699_920_000 + Double(offset) * 86400 + hour * 3600)
    }

    private func makeModel() -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        return (store, TrainingModel(stores: stores, athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)))
    }

    /// A calendar export file with two planned workouts, written to a temporary file.
    private func writeExportFile(name: String = "Training Calendar.json", editing edit: (String) -> String = { $0 }) async throws -> URL {
        let (store, source) = makeModel()
        let workout = try BuiltInWorkoutTemplates.shortIntervalRun.instantiate()
        try await store.upsert([workout])
        try await store.upsert([PlannedActivity(workoutID: workout.id, date: day(4)), PlannedActivity(workoutID: workout.id, date: day(5))])
        let export = try await source.calendarExport(from: day(0), through: day(6), asOf: day(3, hour: 9))
        let json = edit(try #require(String(data: export.jsonData(), encoding: .utf8)))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString) \(name)")
        try Data(json.utf8).write(to: url)
        return url
    }

    @Test("choosing a file previews the import and saves nothing")
    func previewSavesNothing() async throws {
        let url = try await writeExportFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let (store, model) = makeModel()
        let viewModel = CalendarImportViewModel(model: model, today: day(3, hour: 9))

        await viewModel.load(from: url)

        guard case .preview(_, let report) = viewModel.state else { Issue.record("state was \(viewModel.state)"); return }
        #expect(report.added == 2)
        #expect(viewModel.canImport)
        #expect(try await store.plans(in: day(0)...day(6)).isEmpty)
    }

    @Test("confirming imports the previewed plans, and importing the same file again would add none")
    func importThenNothingToAdd() async throws {
        let url = try await writeExportFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let (store, model) = makeModel()
        try await model.load(in: day(0)...day(6), asOf: day(3, hour: 9))
        let viewModel = CalendarImportViewModel(model: model, today: day(3, hour: 9))
        await viewModel.load(from: url)

        await viewModel.performImport()

        guard case .imported(let report) = viewModel.state else { Issue.record("state was \(viewModel.state)"); return }
        #expect(report.added == 2)
        #expect(try await store.plans(in: day(0)...day(6)).count == 2)
        #expect(model.plans.count == 2)

        viewModel.reset()
        await viewModel.load(from: url)
        guard case .preview(_, let again) = viewModel.state else { Issue.record("state was \(viewModel.state)"); return }
        #expect(again.added == 0 && again.skippedDuplicates == 2)
        #expect(!viewModel.canImport, "nothing to add, so the confirm button stays disabled")
    }

    @Test("a file that isn't an export fails with a message and offers choosing again")
    func notAnExport() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let (_, model) = makeModel()
        let viewModel = CalendarImportViewModel(model: model, today: day(3))

        await viewModel.load(from: url)

        #expect(viewModel.state == .failed("This file isn't a Training Calendar export."))
        #expect(!viewModel.canImport)
        viewModel.reset()
        #expect(viewModel.state == .idle)
    }

    @Test("a file from a newer version of the app is refused with its own message")
    func newerVersion() async throws {
        let url = try await writeExportFile { $0.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 9") }
        defer { try? FileManager.default.removeItem(at: url) }
        let (_, model) = makeModel()
        let viewModel = CalendarImportViewModel(model: model, today: day(3))

        await viewModel.load(from: url)

        #expect(viewModel.state == .failed("This file was made by a newer version of the app. Update the app to import it."))
    }

    @Test("a missing file fails instead of crashing")
    func missingFile() async {
        let (_, model) = makeModel()
        let viewModel = CalendarImportViewModel(model: model, today: day(3))

        await viewModel.load(from: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json"))

        #expect(viewModel.state == .failed("The file couldn't be read. Please try again."))
    }

    @Test("importing without a preview does nothing")
    func importWithoutPreview() async {
        let (store, model) = makeModel()
        let viewModel = CalendarImportViewModel(model: model, today: day(3))

        await viewModel.performImport()

        #expect(viewModel.state == .idle)
        #expect((try? await store.workouts().isEmpty) == true)
    }

    @Test("a second import call while one is running is a no-op")
    func concurrentImportGuarded() async throws {
        let url = try await writeExportFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let (store, model) = makeModel()
        let viewModel = CalendarImportViewModel(model: model, today: day(3, hour: 9))
        await viewModel.load(from: url)

        async let first: Void = viewModel.performImport()
        async let second: Void = viewModel.performImport()
        _ = await (first, second)

        #expect(try await store.plans(in: day(0)...day(6)).count == 2, "not imported twice")
    }
}
