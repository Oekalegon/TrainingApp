import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@Suite("Workout step cards (MVP2-143)")
struct WorkoutBlockCardTests {
    @Test("a repeated block is a group; single steps run once are plain cards; steps are numbered across blocks")
    func groupsAndNumbering() throws {
        let workout = try BuiltInWorkoutTemplates.shortIntervalRun.instantiate()

        let cards = WorkoutBlockCard.cards(for: workout.blocks)

        #expect(cards.map(\.isGroup) == [false, false, true, false])
        #expect(cards.map(\.repetitions) == [1, 1, 8, 1])
        #expect(cards.flatMap(\.steps).map(\.id) == Array(0..<5))
        let repeatCard = cards[2]
        #expect(repeatCard.steps.map(\.title) == ["Work", "Recovery"])
        #expect(repeatCard.steps.map(\.detail) == ["1:00", "1:30"])
        #expect(repeatCard.steps.map(\.target) == ["HR Zone 5", "HR Zone 1"])
    }

    @Test("a step says what ends it: time, distance or open, and its target")
    func stepText() {
        let blocks = [WorkoutBlock(steps: [
            WorkoutStep(kind: .warmup, goal: .time(300), target: .heartRateZone(1)),
            WorkoutStep(kind: .work, goal: .distance(400), target: .heartRateRange(140, 150)),
            WorkoutStep(kind: .work, goal: .open),
            WorkoutStep(kind: .cooldown, goal: .open, target: .rpe(3))
        ])]

        let steps = WorkoutBlockCard.cards(for: blocks)[0].steps

        #expect(steps.map(\.title) == ["Warm-up", "Work", "Work", "Cool-down"])
        #expect(steps.map(\.detail) == ["5:00", "400 m", "Open", "Open"])
        #expect(steps.map(\.target) == ["HR Zone 1", "140–150 bpm", nil, "RPE 3"])
        #expect(steps.map(\.end) == [.time, .distance, .open, .open])
        #expect(steps.map(\.targetSymbol) == ["heart.fill", "heart.fill", nil, "scope"])
        #expect(WorkoutBlockCard.targetSymbol(.pace(3.0...3.5)) == WorkoutBlockCard.paceSymbol)
        #expect(WorkoutBlockCard.targetSymbol(.power(200...250)) == "bolt.fill")
        // Several steps in one block belong together even when it runs once.
        #expect(WorkoutBlockCard.cards(for: blocks)[0].isGroup)
    }

    @Test("no blocks, no cards")
    func empty() {
        #expect(WorkoutBlockCard.cards(for: []).isEmpty)
    }

    @Test("a draft's card names a parameter and its starting value instead of a number")
    func draftCardsShowParameters() {
        var draft = WorkoutTemplateDraft(name: "x")
        let effort = WorkoutTemplateDraft.Parameter(key: "e", name: "Effort", unit: .minutes, defaultValue: 1, lowerBound: 0.5, upperBound: 2)
        let reps = WorkoutTemplateDraft.Parameter(key: "r", name: "Repeats", unit: .count, defaultValue: 8, lowerBound: 6, upperBound: 12)
        draft.parameters = [effort, reps]
        let step = WorkoutTemplateDraft.Step(kind: .work, goal: .time(.parameter(effort.id)), target: .zone(4))
        let fixed = WorkoutTemplateDraft.Step(kind: .recovery, goal: .distance(.fixed(200)))
        let block = WorkoutTemplateDraft.Block(steps: [step, fixed], repetitions: .parameter(reps.id))

        #expect(draft.card(for: step, number: 3) == WorkoutStepCard(id: 3, kind: .work, title: "Work", detail: "Effort · 1:00", end: .time, target: "HR Zone 4", targetSymbol: "heart.fill"))
        #expect(draft.card(for: fixed, number: 4).detail == "200 m")
        #expect(draft.card(for: fixed, number: 4).end == .distance)
        #expect(draft.repetitionsText(block) == "Repeats · 8")
        #expect(draft.repetitionsText(.init(steps: [], repetitions: .fixed(5))) == "5")
    }

    @Test("removing a step by id leaves the others in order")
    @MainActor
    func removeStepByID() async {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store, templateStore: store
        )
        let editor = WorkoutTemplateEditorViewModel(model: TrainingModel(stores: stores, athlete: .fixture()))
        let block = editor.draft.blocks[0].id
        editor.addStep(toBlock: block)
        editor.draft.blocks[0].steps[1].kind = .recovery

        editor.removeStep(id: editor.draft.blocks[0].steps[0].id, fromBlock: block)

        #expect(editor.draft.blocks[0].steps.map(\.kind) == [.recovery])
    }

    @Test("Add Step adds a step that runs once; Add Repeat adds a repeating work and recovery pair")
    @MainActor
    func addStepAndRepeat() async {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store, templateStore: store
        )
        let editor = WorkoutTemplateEditorViewModel(model: TrainingModel(stores: stores, athlete: .fixture()))
        editor.addBlock()
        editor.addRepeat()

        let blocks = editor.draft.blocks
        #expect(blocks.count == 3)
        #expect(blocks[1].repetitions == .fixed(1))
        #expect(blocks[2].steps.map(\.kind) == [.work, .recovery])
        #expect(blocks[2].repetitions == .fixed(4))
    }

    @Test("a step can be made to repeat, and removing a block's last step removes the block")
    @MainActor
    func repeatAndEmptyBlock() async {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store, templateStore: store
        )
        let editor = WorkoutTemplateEditorViewModel(model: TrainingModel(stores: stores, athlete: .fixture()))
        let block = editor.draft.blocks[0].id

        editor.setRepetitions(3, inBlock: block)
        #expect(editor.draft.blocks[0].repetitions == .fixed(3))

        editor.removeStep(id: editor.draft.blocks[0].steps[0].id, fromBlock: block)
        #expect(editor.draft.blocks.isEmpty)

        editor.addBlock()
        editor.removeSteps(at: IndexSet(integer: 0), fromBlock: editor.draft.blocks[0].id)
        #expect(editor.draft.blocks.isEmpty)
    }
}
