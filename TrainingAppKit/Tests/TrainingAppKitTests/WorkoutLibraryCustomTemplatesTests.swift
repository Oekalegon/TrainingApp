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

    @Test("deleting a custom template keeps the plans made from it; a built-in one can't be deleted")
    func deleteKeepsPlans() async throws {
        let (store, model) = await makeModel()
        let library = makeLibrary(model)
        let template = custom("Steady")
        try await model.add(template)
        let sheet = library.makePlanner(for: template, date: .now)
        #expect(await sheet.save())
        #expect(model.plans.count == 1)

        await library.deleteTemplate(id: BuiltInWorkoutTemplates.easyRun.id)
        #expect(library.templates.contains(BuiltInWorkoutTemplates.easyRun))

        await library.deleteTemplate(id: template.id)

        #expect(!library.templates.contains(template))
        #expect(try await store.template(id: template.id) == nil)
        #expect(model.plans.count == 1)
        #expect(library.actionError == nil)
    }
}
