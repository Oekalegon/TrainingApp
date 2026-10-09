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

    @Test("a duplicate gets a new id and a Copy name, titled after the original until it is renamed")
    func duplicateIsANewTemplate() throws {
        let original = BuiltInWorkoutTemplates.easyRun
        let copy = try #require(WorkoutTemplateDraft(original, duplicating: true).build())

        #expect(copy.id != original.id)
        #expect(copy.name == "Easy run Copy")
        #expect(copy.blocks == original.blocks)
        #expect(copy.parameters == original.parameters)
        // Planned titles don't say "Copy".
        #expect(copy.defaultTitle() == original.defaultTitle())

        var renamed = WorkoutTemplateDraft(original, duplicating: true)
        renamed.name = "My easy run"
        #expect(try #require(renamed.build()).titleName == nil)
        #expect(try #require(renamed.build()).defaultTitle().contains("My Easy Run"))

        // Editing keeps the short title whatever the name.
        var hills = WorkoutTemplateDraft(BuiltInWorkoutTemplates.all.first { $0.titleName != nil } ?? original)
        hills.name = "Renamed"
        #expect(hills.build()?.titleName == BuiltInWorkoutTemplates.all.first { $0.titleName != nil }?.titleName)
    }

    @Test("a blank draft needs a name; a name makes it a valid one-step template")
    func blankDraft() throws {
        var draft = WorkoutTemplateDraft.blank()
        #expect(draft.issues == ["Give the workout template a name."])
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

        let duration = WorkoutTemplateDraft.Parameter(
            key: "p", name: "Duration", unit: .minutes, defaultValue: 50, lowerBound: 10, upperBound: 40
        )
        draft.blocks = [.init(steps: [.init(kind: .work, goal: .time(.parameter(duration.id)))])]
        draft.parameters = [duration]
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
        #expect(again.title == "Edit Workout Template")
    }

    @Test("a second save while the first is running is ignored")
    func doubleSave() async {
        let (_, model) = await makeModel()
        let editor = WorkoutTemplateEditorViewModel(model: model)
        editor.draft.name = "Steady"
        var saved = 0
        editor.onSaved = { saved += 1 }

        async let first = editor.save()
        async let second = editor.save()
        let results = await [first, second]

        #expect(results.filter { $0 }.count == 1)
        #expect(saved == 1)
    }

    @Test("hasChanges follows the draft, and the summary checks it once for issues and title")
    func changesAndSummary() async {
        let (_, model) = await makeModel()
        let editor = WorkoutTemplateEditorViewModel(model: model)
        editor.distanceSystem = .metric
        #expect(!editor.hasChanges)
        #expect(editor.summary.issues == ["Give the workout template a name."])
        #expect(editor.summary.defaultTitle == nil)

        editor.draft.name = "easy run"
        #expect(editor.hasChanges)
        #expect(editor.summary.issues.isEmpty)
        #expect(editor.summary.defaultTitle == "10min Easy Run")

        editor.draft.name = ""
        #expect(editor.hasChanges == false)
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
        #expect(editor.saveError?.hasPrefix("Couldn't save this workout template") == true)
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

    @Test("a parameter nothing uses is dropped: by the editor after a value stops using it, and by build")
    func unusedParametersAreDropped() async throws {
        let (_, model) = await makeModel()
        let editor = WorkoutTemplateEditorViewModel(model: model)
        editor.draft.name = "x"
        let effort = editor.addParameter(unit: .minutes, name: "Effort")
        editor.draft.blocks[0].steps[0].goal = .time(.parameter(effort))
        #expect(editor.draft.parameters.map(\.name) == ["Effort"])

        // The value goes back to fixed, as the picker does.
        editor.draft.blocks[0].steps[0].goal = .time(.fixed(20))
        editor.pruneUnusedParameters()
        #expect(editor.draft.parameters.isEmpty)

        // An orphan neither blocks saving nor reaches the template.
        var draft = WorkoutTemplateDraft(name: "x", blocks: [.init(steps: [.standard])])
        draft.parameters = [.init(key: "orphan", name: "", unit: .count, defaultValue: 99, lowerBound: 5, upperBound: 1)]
        #expect(draft.issues.isEmpty)
        #expect(try #require(draft.build()).parameters.isEmpty)
    }

    @Test("two parameters of one kind get different names; a step can have a duration and a repeat parameter")
    func parameterNamesAndMultipleParametersPerStep() async throws {
        let (_, model) = await makeModel()
        let editor = WorkoutTemplateEditorViewModel(model: model)
        editor.draft.name = "x"
        let first = editor.addParameter(unit: .minutes, name: "Recovery duration")
        let second = editor.addParameter(unit: .minutes, name: "Recovery duration")
        let reps = editor.addParameter(unit: .count, name: "Work repeats")
        #expect(editor.draft.parameters.map(\.name) == ["Recovery duration", "Recovery duration 2", "Work repeats"])
        #expect(first != second)

        // One single-step block with both a duration and a repeat count as parameters.
        editor.draft.blocks[0].steps[0].goal = .time(.parameter(first))
        editor.draft.blocks[0].repetitions = .parameter(reps)
        editor.pruneUnusedParameters()

        #expect(editor.draft.parameters.map(\.name) == ["Recovery duration", "Work repeats"])
        let template = try #require(editor.draft.build())
        #expect(template.parameters.map(\.unit) == [.minutes, .count])
        #expect(try template.instantiate().blocks[0].repetitions == 4)
    }

    @Test("removing the step that used a parameter removes the parameter")
    func removingAStepRemovesItsParameter() async {
        let (_, model) = await makeModel()
        let editor = WorkoutTemplateEditorViewModel(model: model)
        editor.addBlock()
        let id = editor.addParameter(unit: .minutes, name: "Rest")
        editor.draft.blocks[1].steps[0].goal = .time(.parameter(id))

        editor.removeBlock(id: editor.draft.blocks[1].id)

        #expect(editor.draft.parameters.isEmpty)
    }

    @Test("a parameter made from a fixed value starts at that value, with a range around it")
    func parameterStartsFromFixedValue() async throws {
        let (_, model) = await makeModel()
        let editor = WorkoutTemplateEditorViewModel(model: model)
        let duration = editor.addParameter(unit: .minutes, name: "Rest", defaultValue: 5)
        let distance = editor.addParameter(unit: .meters, name: "Rep", defaultValue: 400)
        let count = editor.addParameter(unit: .count, name: "Reps", defaultValue: 6)
        let unusable = editor.addParameter(unit: .count, name: "Odd", defaultValue: 0)

        func parameter(_ id: UUID) throws -> WorkoutTemplateDraft.Parameter {
            try #require(editor.draft.parameters.first { $0.id == id })
        }
        #expect(try (parameter(duration).lowerBound, parameter(duration).defaultValue, parameter(duration).upperBound) == (2.5, 5, 10))
        #expect(try (parameter(distance).lowerBound, parameter(distance).upperBound) == (200, 800))
        #expect(try (parameter(count).lowerBound, parameter(count).defaultValue, parameter(count).upperBound) == (4, 6, 10))
        // No usable value: the unit's usual start.
        #expect(try (parameter(unusable).lowerBound, parameter(unusable).defaultValue, parameter(unusable).upperBound) == (2, 4, 10))
    }
}
