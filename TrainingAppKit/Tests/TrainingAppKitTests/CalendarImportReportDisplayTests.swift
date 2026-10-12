import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("CalendarImportReport display", .serialized)
struct CalendarImportReportDisplayTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_699_920_000 + Double(offset) * 86400)
    }

    private func makeModel() -> TrainingModel {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store, templateStore: store
        )
        return TrainingModel(stores: stores, athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190))
    }

    private func customTemplate() -> WorkoutTemplate {
        WorkoutTemplate(
            name: "Custom", sport: .running,
            parameters: [WorkoutTemplateParameter(key: "minutes", name: "Minutes", unit: .minutes, defaultValue: 30)],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.parameter("minutes")))])]
        )
    }

    /// An export of one plan built from `template`, made on a model that has it.
    private func export(using template: WorkoutTemplate) async throws -> CalendarExport {
        let source = makeModel()
        try await source.add(template)
        let workout = try template.instantiate(values: ["minutes": 40])
        try await source.add(workout)
        try await source.add(PlannedActivity(workoutID: workout.id, date: day(4)))
        return try await source.calendarExport(
            from: day(0), through: day(6), templates: source.knownTemplates, asOf: day(0)
        )
    }

    @Test("a file with a template the library lacks shows it as added in the preview and in the result")
    func addedTemplateRow() async throws {
        let template = customTemplate()
        let file = try await export(using: template)
        let target = makeModel()

        let preview = try await target.calendarImportPreview(file, asOf: day(0))
        #expect(preview.templateRows(future: true) == [.init(title: "Templates that will be added", count: 1)])

        let result = try await target.importCalendar(file, asOf: day(0))
        #expect(result.templateRows(future: false) == [.init(title: "Templates added", count: 1)])
        // What the athlete finds afterwards: the template in the library, and the plan's workout linked to it.
        #expect(target.templates.map(\.id) == [template.id])
        #expect(target.workouts.first?.templateID == template.id)
    }

    @Test("every rejection reason has an explanation, including a completed activity without a start or duration (MVP2-107)")
    func rejectionExplanations() {
        for reason in [CalendarImportReport.RejectionReason.noSteps, .invalidStep, .invalidDate, .invalidActivity] {
            #expect(!reason.explanation.isEmpty)
        }
        #expect(CalendarImportReport.RejectionReason.invalidActivity.explanation == "No start time or duration")
    }

    @Test("a template the library already has is shown as already there")
    func linkedTemplateRow() async throws {
        let template = customTemplate()
        let file = try await export(using: template)
        let target = makeModel()
        try await target.add(template)

        let preview = try await target.calendarImportPreview(file, asOf: day(0))

        #expect(preview.templateRows(future: true) == [.init(title: "Templates already in your library", count: 1)])
    }

    @Test("a file without custom templates shows no template rows")
    func noTemplateRows() async throws {
        let source = makeModel()
        let workout = try BuiltInWorkoutTemplates.shortIntervalRun.instantiate()
        try await source.add(workout)
        try await source.add(PlannedActivity(workoutID: workout.id, date: day(4)))
        let file = try await source.calendarExport(from: day(0), through: day(6), asOf: day(0))

        let preview = try await makeModel().calendarImportPreview(file, asOf: day(0))

        #expect(preview.templateRows(future: true).isEmpty)
        #expect(preview.templateRows(future: false).isEmpty)
    }

    @Test("a different template with the same id is added as a copy, and the rows say so")
    func copiedTemplateRow() async throws {
        let template = customTemplate()
        let file = try await export(using: template)
        let target = makeModel()
        var clashing = template
        clashing.blocks = [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.fixed(60)))])]
        try await target.add(clashing)

        let preview = try await target.calendarImportPreview(file, asOf: day(0))
        #expect(preview.templateRows(future: true).map(\.count) == [1])
        #expect(preview.templateRows(future: true).first?.title.hasPrefix("Templates that will be added as copies") == true)

        let result = try await target.importCalendar(file, asOf: day(0))
        #expect(result.templateRows(future: false).first?.title.hasPrefix("Templates added as copies") == true)
        #expect(target.templates.count == 2)
    }

    @Test("without a template store a template can't be used, and the row says the workouts keep their steps")
    func rejectedTemplateRow() async throws {
        let file = try await export(using: customTemplate())
        let store = InMemoryStore()
        let target = TrainingModel(
            stores: StoreSet(
                activityStore: store, planStore: store, workoutStore: store,
                cycleStore: store, raceStore: store, athleteStore: store
            ),
            athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        )

        let result = try await target.importCalendar(file, asOf: day(0))

        #expect(result.templateRows(future: false) == [
            .init(title: "Templates that can't be used (workouts keep their steps)", count: 1),
        ])
        #expect(target.workouts.first?.templateID == nil)
    }
}
