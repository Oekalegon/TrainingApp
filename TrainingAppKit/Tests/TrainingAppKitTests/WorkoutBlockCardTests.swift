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
        #expect(steps.map(\.targetSymbol) == ["heart.fill", "heart.fill", nil, "bolt.fill"])
        #expect(WorkoutBlockCard.targetSymbol(.pace(3.0...3.5)) == WorkoutBlockCard.paceSymbol)
        #expect(WorkoutBlockCard.targetSymbol(.power(200...250)) == "bolt.horizontal.fill")
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

    @Test("a new template starts with a 5 minute warm-up and cool-down and nothing between them")
    func starterDraft() throws {
        var draft = WorkoutTemplateDraft.starter()
        draft.name = "x"
        #expect(draft.issues == ["Add at least one work or recovery step."])
        #expect(draft.build() == nil)

        draft.blocks.insert(.init(steps: [.standard]), at: draft.insertionIndex)
        let template = try #require(draft.build())

        #expect(template.blocks.map { $0.steps[0].kind } == [.warmup, .work, .cooldown])
        #expect(template.blocks[0].steps[0].goal == .time(.fixed(300)))
        #expect(template.blocks[2].steps[0].goal == .time(.fixed(300)))
        #expect(template.blocks[0].steps[0].target == .heartRateZone(1))
    }

    @Test("steps and repeats added to a new template go between its warm-up and cool-down")
    @MainActor
    func additionsStayBeforeCooldown() async {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store, templateStore: store
        )
        let editor = WorkoutTemplateEditorViewModel(
            model: TrainingModel(stores: stores, athlete: .fixture()), draft: .starter()
        )

        let step = editor.addBlock()
        let repeatStep = editor.addRepeat()

        #expect(editor.draft.blocks.map { $0.steps[0].kind } == [.warmup, .work, .work, .cooldown])
        #expect(editor.draft.blocks[1].steps[0].id == step)
        #expect(editor.draft.blocks[2].steps[0].id == repeatStep)
        #expect(editor.draft.blocks[2].repetitions == .fixed(4))
        #expect(editor.draft.leadingBlockIndex == 0)
        #expect(editor.draft.trailingBlockIndex == 3)
        #expect(editor.draft.movableRange == 1..<3)
        // The cool-down can be removed like any step, after which additions go last again.
        editor.removeBlock(id: editor.draft.blocks[3].id)
        editor.addBlock()
        #expect(editor.draft.blocks.count == 4)
        #expect(editor.draft.blocks.last?.steps[0].kind == .work)
        #expect(editor.draft.trailingBlockIndex == nil)
    }

    @Test("the warm-up and cool-down never move, and nothing moves past them")
    func pinnedBlocks() {
        func block(_ kind: StepKind) -> WorkoutTemplateDraft.Block {
            .init(steps: [.init(kind: kind, goal: .open)])
        }
        let warmup = block(.warmup), first = block(.work), second = block(.recovery), third = block(.work), cooldown = block(.cooldown)
        var draft = WorkoutTemplateDraft(name: "x", blocks: [warmup, first, second, third, cooldown])
        #expect(draft.isPinned(blockID: warmup.id))
        #expect(draft.isPinned(blockID: cooldown.id))
        #expect(!draft.isPinned(blockID: second.id))

        // Dropped on another: dragged down it lands after, dragged up before.
        draft.moveBlock(id: first.id, toPositionOf: third.id)
        #expect(draft.blocks.map(\.id) == [warmup.id, second.id, third.id, first.id, cooldown.id])
        draft.moveBlock(id: first.id, toPositionOf: second.id)
        #expect(draft.blocks.map(\.id) == [warmup.id, first.id, second.id, third.id, cooldown.id])

        // Pinned ones can't be dragged, nor dropped on.
        draft.moveBlock(id: warmup.id, toPositionOf: second.id)
        draft.moveBlock(id: cooldown.id, toPositionOf: first.id)
        draft.moveBlock(id: first.id, toPositionOf: cooldown.id)
        draft.moveBlock(id: second.id, toPositionOf: warmup.id)
        #expect(draft.blocks.map(\.id) == [warmup.id, first.id, second.id, third.id, cooldown.id])

        // Up and down stop at the ends of the movable ones.
        draft.moveBlock(id: first.id, by: -1)
        draft.moveBlock(id: third.id, by: 1)
        #expect(draft.blocks.map(\.id) == [warmup.id, first.id, second.id, third.id, cooldown.id])
        draft.moveBlock(id: third.id, by: -1)
        #expect(draft.blocks.map(\.id) == [warmup.id, first.id, third.id, second.id, cooldown.id])
        draft.moveBlock(id: first.id, by: 1)
        #expect(draft.blocks.map(\.id) == [warmup.id, third.id, first.id, second.id, cooldown.id])
    }

    @Test("a warm-up that isn't first, or a cool-down that isn't last, isn't pinned")
    func onlyTheEndsArePinned() {
        let a = WorkoutTemplateDraft.Block(steps: [.init(kind: .work, goal: .open)])
        let warmup = WorkoutTemplateDraft.Block(steps: [.init(kind: .warmup, goal: .open)])
        let draft = WorkoutTemplateDraft(name: "x", blocks: [a, warmup])
        #expect(draft.leadingBlockIndex == nil)
        #expect(draft.trailingBlockIndex == nil)
        #expect(draft.movableRange == 0..<2)
        // A warm-up inside a block with other steps isn't a lone warm-up either.
        let mixed = WorkoutTemplateDraft.Block(steps: [.init(kind: .warmup, goal: .open), .init(kind: .work, goal: .open)])
        #expect(WorkoutTemplateDraft(name: "x", blocks: [mixed]).leadingBlockIndex == nil)
    }

    @Test("a removed warm-up and cool-down can be put back, at the top and bottom")
    @MainActor
    func reinsertWarmupAndCooldown() async throws {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store, templateStore: store
        )
        let editor = WorkoutTemplateEditorViewModel(
            model: TrainingModel(stores: stores, athlete: .fixture()), draft: .starter()
        )
        editor.addBlock()
        // Already there: nothing is added.
        #expect(editor.addWarmup() == nil)
        #expect(editor.addCooldown() == nil)

        editor.removeBlock(id: editor.draft.blocks[0].id)
        editor.removeBlock(id: editor.draft.blocks.last!.id)
        #expect(editor.draft.blocks.map { $0.steps[0].kind } == [.work])
        #expect(editor.draft.leadingBlockIndex == nil)
        #expect(editor.draft.trailingBlockIndex == nil)

        let warmup = try #require(editor.addWarmup())
        let cooldown = try #require(editor.addCooldown())

        #expect(editor.draft.blocks.map { $0.steps[0].kind } == [.warmup, .work, .cooldown])
        #expect(editor.draft.blocks[0].steps[0].id == warmup)
        #expect(editor.draft.blocks[2].steps[0].id == cooldown)
        #expect(editor.draft.blocks[0].steps[0].goal == .time(.fixed(5)))
        #expect(editor.draft.movableRange == 1..<2)
    }
}
