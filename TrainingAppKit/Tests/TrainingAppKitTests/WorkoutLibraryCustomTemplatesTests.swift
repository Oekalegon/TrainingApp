import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("Library with custom templates (MVP2-140)")
struct WorkoutLibraryCustomTemplatesTests {
    private func makeModel() async -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store, templateStore: store
        )
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        try? await store.save(athlete)
        return (store, TrainingModel(stores: stores, athlete: athlete))
    }

    private func makeLibrary(_ model: TrainingModel) -> WorkoutLibraryViewModel {
        let library = WorkoutLibraryViewModel(model: model, scheduler: { nil })
        library.distanceSystem = .metric
        return library
    }

    private func custom(_ name: String, sport: Sport = .running) -> WorkoutTemplate {
        WorkoutTemplate(
            name: name, sport: sport, parameters: [],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.fixed(1800)), target: .heartRateZone(2))])]
        )
    }

    @Test("custom templates follow the built-in ones, by name, and are marked custom")
    func customTemplatesAreListed() async throws {
        let (_, model) = await makeModel()
        let library = makeLibrary(model)
        try await model.add(custom("Zebra"))
        try await model.add(custom("Alpha"))

        let templates = library.templates
        #expect(Array(templates.prefix(BuiltInWorkoutTemplates.all.count)) == BuiltInWorkoutTemplates.all)
        #expect(templates.suffix(2).map(\.name) == ["Alpha", "Zebra"])
        let entries = library.entries()
        #expect(entries.filter(\.isCustom).map(\.template.name) == ["Alpha", "Zebra"])
        #expect(entries.filter { !$0.isCustom }.count == BuiltInWorkoutTemplates.all.count)
    }

    @Test("a custom template for a sport the built-ins don't cover gets a section of its own")
    func customSport() async throws {
        let (_, model) = await makeModel()
        let library = makeLibrary(model)
        try await model.add(custom("Easy spin", sport: .cycling))

        let section = try #require(library.sections().first { $0.sport == .cycling })
        #expect(section.entries.map(\.template.name) == ["Easy spin"])
    }

    @Test("the planned-workout sheet offers custom templates, and its edit mode finds the template of a plan")
    func sheetOffersCustomTemplates() async throws {
        let (_, model) = await makeModel()
        let template = custom("Steady")
        try await model.add(template)

        let sheet = PlannedWorkoutSheetViewModel(model: model, scheduler: nil)
        #expect(sheet.templates.contains(template))
        sheet.selectedTemplate = template
        #expect(await sheet.save())

        let plan = try #require(model.plans.first)
        let editor = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: nil)
        #expect(editor.templates.contains(template))
    }

    @Test("Edit replaces a custom template; for a built-in one it makes a copy")
    func editorForCustomAndBuiltIn() async throws {
        let (_, model) = await makeModel()
        let library = makeLibrary(model)
        let mine = custom("Steady")
        try await model.add(mine)

        let editMine = library.makeEditor(for: mine)
        #expect(!editMine.isNew)
        #expect(editMine.draft.id == mine.id)
        #expect(editMine.draft.name == "Steady")

        let editBuiltIn = library.makeEditor(for: BuiltInWorkoutTemplates.easyRun)
        #expect(editBuiltIn.isNew)
        #expect(editBuiltIn.draft.id != BuiltInWorkoutTemplates.easyRun.id)
        #expect(editBuiltIn.draft.name == "Easy run Copy")

        let copyMine = library.makeEditorDuplicating(mine)
        #expect(copyMine.isNew)
        #expect(copyMine.draft.id != mine.id)
        #expect(copyMine.distanceSystem == .metric)
    }

    @Test("a saved copy appears in the library next to the original")
    func duplicateAppears() async throws {
        let (_, model) = await makeModel()
        let library = makeLibrary(model)
        let mine = custom("Steady")
        try await model.add(mine)

        let copy = library.makeEditorDuplicating(mine)
        #expect(await copy.save())

        #expect(library.entries().filter(\.isCustom).map(\.template.name) == ["Steady", "Steady Copy"])
    }

    @Test("deleting a template that plans use archives it: hidden from the library and picker, still known to plan editing and export")
    func deleteArchivesUsedTemplate() async throws {
        let (store, model) = await makeModel()
        let library = makeLibrary(model)
        let template = WorkoutTemplate(
            name: "Steady", sport: .running,
            parameters: [WorkoutTemplateParameter(key: "d", name: "Duration", unit: .minutes, defaultValue: 1800, range: 600...3600)],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.parameter("d")), target: .heartRateZone(2))])]
        )
        try await model.add(template)
        let sheet = library.makePlanner(for: template, date: .now)
        #expect(await sheet.save())
        #expect(model.plans.count == 1)

        #expect(await library.deleteTemplate(id: BuiltInWorkoutTemplates.easyRun.id) == nil)
        #expect(library.templates.contains(BuiltInWorkoutTemplates.easyRun))

        #expect(await library.deleteTemplate(id: template.id) == .archived)

        #expect(try await store.template(id: template.id)?.isArchived == true)
        #expect(!library.templates.contains { $0.id == template.id })
        #expect(!library.entries().contains { $0.id == template.id })
        #expect(library.entries(matching: "Steady").isEmpty)
        #expect(!PlannedWorkoutSheetViewModel(model: model, scheduler: nil).templates.contains { $0.id == template.id })
        #expect(model.knownTemplates.contains { $0.id == template.id })
        // The plan still edits its parameters.
        let editor = PlannedWorkoutSheetViewModel(model: model, editing: try #require(model.plans.first), scheduler: nil)
        #expect(editor.canEditParameters)
        #expect(!editor.templateIsMissing)
        // And an export still names the template.
        let export = try await model.calendarExport(
            from: .now.addingTimeInterval(-86400), through: .now.addingTimeInterval(86400 * 2), templates: model.knownTemplates
        )
        #expect(export.days.flatMap(\.activities).contains { $0.template == "Steady" })
        #expect(library.actionError == nil)
    }

    @Test("a template no plan uses is removed outright")
    func deleteUnusedTemplate() async throws {
        let (store, model) = await makeModel()
        let library = makeLibrary(model)
        let template = custom("Steady")
        try await model.add(template)

        #expect(await library.deleteTemplate(id: template.id) == .deleted)

        #expect(try await store.template(id: template.id) == nil)
        #expect(!library.templates.contains(template))
    }

    @Test("a plan made before its template was edited takes the template's new structure when its parameters change")
    func planEditUsesCurrentTemplate() async throws {
        let (_, model) = await makeModel()
        var template = WorkoutTemplate(
            name: "Steady", sport: .running,
            parameters: [WorkoutTemplateParameter(key: "d", name: "Duration", unit: .minutes, defaultValue: 1800, range: 600...3600)],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.parameter("d")), target: .heartRateZone(2))])]
        )
        try await model.add(template)
        let planner = PlannedWorkoutSheetViewModel(model: model, scheduler: nil)
        planner.selectedTemplate = template
        #expect(await planner.save())

        // The athlete adds a cooldown to the template.
        template.blocks.append(TemplateBlock(steps: [TemplateStep(kind: .cooldown, goal: .time(.fixed(300)))]))
        try await model.add(template)

        let editor = PlannedWorkoutSheetViewModel(model: model, editing: try #require(model.plans.first), scheduler: nil)
        editor.setParameterValue(2400, forKey: "d")
        #expect(await editor.save())

        let plan = try #require(model.plans.first)
        let workout = try #require(model.workouts.first { $0.id == plan.workoutID })
        #expect(workout.blocks.count == 2)
    }

    @Test("a plan whose template no longer exists says so")
    func missingTemplate() async throws {
        let (store, model) = await makeModel()
        let template = custom("Steady")
        let workout = try template.instantiate()
        try await store.upsert([workout])
        let plan = PlannedActivity(workoutID: workout.id, date: .now)
        try await store.upsert([plan])
        try await model.load(in: .now.addingTimeInterval(-86400)...(.now.addingTimeInterval(86400)), asOf: .now)

        let editor = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: nil)

        #expect(!editor.canEditParameters)
        #expect(editor.templateIsMissing)
    }

    @Test("the search tab finds a custom template by name")
    func searchFindsCustom() async throws {
        let (_, model) = await makeModel()
        let library = makeLibrary(model)
        try await model.add(custom("Zebra stripes"))

        #expect(library.entries(matching: "zebra").map(\.template.name) == ["Zebra stripes"])
    }
}
