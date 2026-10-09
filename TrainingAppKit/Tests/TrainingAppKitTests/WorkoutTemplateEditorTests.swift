import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("Workout template creator (MVP2-140)")
struct WorkoutTemplateEditorTests {
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

    @Test("every built-in template survives a trip through a draft unchanged")
    func builtInsRoundTrip() throws {
        for template in BuiltInWorkoutTemplates.all {
            let rebuilt = try #require(WorkoutTemplateDraft(template).build(), "\(template.name)")
            #expect(rebuilt == template, "\(template.name)")
        }
    }

    @Test("a duplicate gets a new id and a Copy name, and no short title")
    func duplicateIsANewTemplate() throws {
        let original = BuiltInWorkoutTemplates.easyRun
        let copy = try #require(WorkoutTemplateDraft(original, duplicating: true).build())

        #expect(copy.id != original.id)
        #expect(copy.name == "Easy run Copy")
        #expect(copy.blocks == original.blocks)
        #expect(copy.parameters == original.parameters)
    }

    @Test("a blank draft needs a name; a name makes it a valid one-step template")
    func blankDraft() throws {
        var draft = WorkoutTemplateDraft.blank()
        #expect(draft.issues == ["Give the workout a name."])
        #expect(draft.build() == nil)

        draft.name = "  Steady 10  "
        let template = try #require(draft.build())
        #expect(template.name == "Steady 10")
        #expect(template.blocks == [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.fixed(600)), target: .heartRateZone(2))])])
    }

    @Test("a parameter drives a step's duration in minutes, saved in seconds, and a block's repeats")
    func parametersAreWired() async throws {
        let (_, model) = await makeModel()
        let editor = WorkoutTemplateEditorViewModel(model: model)
        editor.draft.name = "Intervals"
        let reps = editor.addParameter(unit: .count)
        let work = editor.addParameter(unit: .minutes)
        editor.draft.blocks[0].repetitions = .parameter(reps)
        editor.draft.blocks[0].steps[0].goal = .time(.parameter(work))

        let template = try #require(editor.draft.build())

        #expect(template.parameters.map(\.unit) == [.count, .minutes])
        let minutes = try #require(template.parameters.last)
        #expect(minutes.defaultValue == 20 * 60)
        #expect(minutes.range == Double(600)...Double(2400))
        #expect(template.blocks[0].repetitions == .parameter(template.parameters[0].key))
        #expect(template.blocks[0].steps[0].goal == .time(.parameter(minutes.key)))
        #expect(try template.instantiate().blocks[0].repetitions == 4)
    }

    @Test("removing a parameter turns what used it into its starting value")
    func removeParameter() async {
        let (_, model) = await makeModel()
        let editor = WorkoutTemplateEditorViewModel(model: model)
        let work = editor.addParameter(unit: .minutes)
        editor.draft.blocks[0].steps[0].goal = .time(.parameter(work))

        editor.removeParameter(id: work)

        #expect(editor.draft.parameters.isEmpty)
        #expect(editor.draft.blocks[0].steps[0].goal == .time(.fixed(20)))
    }

    @Test("parameter keys stay unique after one is removed")
    func uniqueKeys() async {
        let (_, model) = await makeModel()
        let editor = WorkoutTemplateEditorViewModel(model: model)
        let first = editor.addParameter(unit: .count)
        editor.addParameter(unit: .minutes)
        editor.removeParameter(id: first)
        editor.addParameter(unit: .meters)

        let keys = editor.draft.parameters.map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    @Test("the draft says what's wrong: no steps, empty block, bad numbers, bad parameter ranges")
    func validation() {
        var draft = WorkoutTemplateDraft(name: "x")
        #expect(draft.issues == ["Add at least one step."])

        draft.blocks = [.init(steps: [.standard]), .init(steps: [])]
        #expect(draft.issues == ["Every block needs a step; remove the empty one."])

        draft.blocks = [.init(steps: [.init(kind: .work, goal: .time(.fixed(0)))], repetitions: .fixed(0.5))]
        #expect(draft.issues.contains("A timed step needs a duration above zero."))
        #expect(draft.issues.contains("A block must repeat a whole number of times, at least once."))

        draft.blocks = [.init(steps: [.init(kind: .work, goal: .distance(.fixed(-1)))])]
        #expect(draft.issues == ["A step with a distance needs a distance above zero."])

        draft.blocks = [.init(steps: [.standard])]
        draft.parameters = [.init(key: "p", name: "Duration", unit: .minutes, defaultValue: 50, lowerBound: 10, upperBound: 40)]
        #expect(draft.issues == ["Duration: the starting value must be within its range."])
        draft.parameters[0].lowerBound = 40
        #expect(draft.issues == ["Duration: the lowest value must be below the highest."])
    }

    @Test("a step pointing at a parameter of the wrong unit is rejected")
    func wrongUnitReference() {
        var draft = WorkoutTemplateDraft(name: "x", blocks: [.init(steps: [.standard])])
        let distance = WorkoutTemplateDraft.Parameter(key: "d", name: "D", unit: .meters, defaultValue: 400, lowerBound: 100, upperBound: 800)
        draft.parameters = [distance]
        draft.blocks[0].steps[0].goal = .time(.parameter(distance.id))

        #expect(draft.issues == ["A step uses a parameter that no longer exists."])
    }

    @Test("a target the editor can't set is kept when its template is edited")
    func preservedTarget() throws {
        let template = WorkoutTemplate(
            name: "Pace work", sport: .running, parameters: [],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .open, target: .pace(3.0...3.5))])]
        )
        #expect(try #require(WorkoutTemplateDraft(template).build()) == template)
    }

    @Test("saving adds the template to the store and the model; editing replaces it")
    func saveAddsThenReplaces() async throws {
        let (store, model) = await makeModel()
        let editor = WorkoutTemplateEditorViewModel(model: model)
        editor.draft.name = "Steady"
        var saved = 0
        editor.onSaved = { saved += 1 }

        #expect(await editor.save())
        let id = editor.draft.id
        #expect(model.templates.map(\.id) == [id])
        #expect(try await store.template(id: id)?.name == "Steady")
        #expect(saved == 1)

        let again = WorkoutTemplateEditorViewModel(
            model: model, draft: WorkoutTemplateDraft(try #require(model.templates.first)), isNew: false
        )
        again.draft.name = "Steady state"
        #expect(await again.save())
        #expect(model.templates.map(\.name) == ["Steady state"])
        #expect(again.title == "Edit Workout")
    }

    @Test("an invalid draft isn't saved")
    func invalidDraftIsNotSaved() async {
        let (_, model) = await makeModel()
        let editor = WorkoutTemplateEditorViewModel(model: model)

        #expect(!editor.canSave)
        #expect(await !editor.save())
        #expect(model.templates.isEmpty)
        #expect(editor.saveError == nil)
    }

    @Test("a store without a template store reports the failure")
    func saveFailure() async {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let editor = WorkoutTemplateEditorViewModel(model: TrainingModel(stores: stores, athlete: .fixture()))
        editor.draft.name = "Steady"

        #expect(await !editor.save())
        #expect(editor.saveError?.hasPrefix("Couldn't save this workout") == true)
    }

    @Test("the default title preview follows the draft")
    func titlePreview() async {
        let (_, model) = await makeModel()
        let editor = WorkoutTemplateEditorViewModel(model: model)
        editor.distanceSystem = .metric
        #expect(editor.defaultTitlePreview == nil)

        editor.draft.name = "easy run"
        #expect(editor.defaultTitlePreview == "10min Easy Run")
    }

    @Test("steps can be added, moved and removed within a block; blocks can be added and removed")
    func structureEdits() async {
        let (_, model) = await makeModel()
        let editor = WorkoutTemplateEditorViewModel(model: model)
        let block = editor.draft.blocks[0].id
        editor.addStep(toBlock: block)
        editor.draft.blocks[0].steps[1].kind = .recovery
        editor.moveSteps(from: IndexSet(integer: 1), to: 0, inBlock: block)
        #expect(editor.draft.blocks[0].steps.map(\.kind) == [.recovery, .work])

        editor.removeSteps(at: IndexSet(integer: 0), fromBlock: block)
        #expect(editor.draft.blocks[0].steps.map(\.kind) == [.work])

        editor.addBlock()
        #expect(editor.draft.blocks.count == 2)
        editor.removeBlock(id: block)
        #expect(editor.draft.blocks.count == 1)
    }
}
