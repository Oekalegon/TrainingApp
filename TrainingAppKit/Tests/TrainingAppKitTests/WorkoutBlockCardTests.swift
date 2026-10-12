import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@Suite("Workout step cards (MVP2-143)")
struct WorkoutBlockCardTests {
    @Test("a repeated block is a group; single steps run once are plain cards; steps are numbered across blocks")
    func groupsAndNumbering() throws {
        let workout = try BuiltInWorkoutTemplates.shortIntervalRun.instantiate()

        let cards = WorkoutBlockCard.cards(for: workout.blocks, distanceSystem: .metric)

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

        let steps = WorkoutBlockCard.cards(for: blocks, distanceSystem: .metric)[0].steps

        #expect(steps.map(\.title) == ["Warm-up", "Work", "Work", "Cool-down"])
        #expect(steps.map(\.detail) == ["5:00", "400 m", "Open", "Open"])
        #expect(steps.map(\.target) == ["HR Zone 1", "140–150 bpm", nil, "RPE 3"])
        #expect(steps.map(\.end) == [.time, .distance, .open, .open])
        #expect(steps.map(\.targetSymbol) == ["heart.fill", "heart.fill", nil, "bolt.fill"])
        #expect(WorkoutBlockCard.targetSymbol(.pace(3.0...3.5)) == WorkoutBlockCard.paceSymbol)
        #expect(WorkoutBlockCard.targetSymbol(.power(200...250)) == "bolt.horizontal.fill")
        // Several steps in one block belong together even when it runs once.
        #expect(WorkoutBlockCard.cards(for: blocks, distanceSystem: .metric)[0].isGroup)
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

        #expect(draft.card(for: step, number: 3) == WorkoutStepCard(id: 3, kind: .work, title: "Work", detail: "Effort · 1:00", end: .time, target: "HR Zone 4", targetSymbol: "heart.fill", parameterName: "Effort"))
        #expect(draft.card(for: fixed, number: 4, distanceSystem: .metric).detail == "200 m")
        #expect(draft.card(for: fixed, number: 4, distanceSystem: .metric).end == .distance)
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

    @Test("cards for a template name the parameters behind its durations, distances and repeats")
    func templateCardsNameParameters() throws {
        let template = BuiltInWorkoutTemplates.shortIntervalRun
        let cards = WorkoutBlockCard.cards(for: template)
        let named = cards.flatMap(\.steps).compactMap(\.parameterName)
        let expected = template.blocks.flatMap(\.steps).compactMap { step -> String? in
            switch step.goal {
            case .time(.parameter(let key)), .distance(.parameter(let key)):
                template.parameters.first { $0.key == key }?.name
            default: nil
            }
        }
        #expect(named == expected)
        #expect(!named.isEmpty)
        #expect(cards.compactMap(\.repetitionsParameterName).count == template.blocks.filter {
            if case .parameter = $0.repetitions { true } else { false }
        }.count)
        // A fixed warm-up has none.
        #expect(cards[0].steps[0].parameterName == nil)
    }

    @Test("a draft card names its parameter, and a fixed value has no name")
    func draftCardParameterName() {
        var draft = WorkoutTemplateDraft(name: "x")
        let effort = WorkoutTemplateDraft.Parameter(key: "e", name: "Effort", unit: .minutes, defaultValue: 1, lowerBound: 0.5, upperBound: 2)
        draft.parameters = [effort]
        let variable = WorkoutTemplateDraft.Step(kind: .work, goal: .time(.parameter(effort.id)))
        let fixed = WorkoutTemplateDraft.Step(kind: .recovery, goal: .time(.fixed(1)))
        #expect(draft.card(for: variable, number: 0).parameterName == "Effort")
        #expect(draft.card(for: fixed, number: 1).parameterName == nil)
        let block = WorkoutTemplateDraft.Block(steps: [variable], repetitions: .parameter(effort.id))
        #expect(draft.parameterName(block.repetitions) == "Effort")
    }

    @Test("distances are written by the chosen system, whatever the machine's locale")
    func distanceSystems() {
        #expect(WorkoutBlockCard.distanceText(400, in: .metric) == "400 m")
        #expect(WorkoutBlockCard.distanceText(20_000, in: .metric) == "20 km")
        #expect(WorkoutBlockCard.distanceText(1_500, in: .metric) == "1.5 km")
        #expect(WorkoutBlockCard.distanceText(400, in: .imperial) == "437.4 yd")
        #expect(WorkoutBlockCard.distanceText(20_000, in: .imperial) == "12.4 mi")
        let blocks = [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(400))])]
        #expect(WorkoutBlockCard.cards(for: blocks, distanceSystem: .metric)[0].steps[0].detail == "400 m")
        #expect(WorkoutBlockCard.cards(for: blocks, distanceSystem: .imperial)[0].steps[0].detail == "437.4 yd")
    }

    @Test("a dragged block swaps with the neighbour its centre has passed, one at a time, and never with a pinned one")
    func swapDecision() {
        func block(_ kind: StepKind) -> WorkoutTemplateDraft.Block { .init(steps: [.init(kind: kind, goal: .open)]) }
        let warmup = block(.warmup), a = block(.work), b = block(.recovery), c = block(.work), cooldown = block(.cooldown)
        let draft = WorkoutTemplateDraft(name: "x", blocks: [warmup, a, b, c, cooldown])
        // Each card 100 high, 10 apart, from the top.
        var frames: [UUID: CGRect] = [:]
        for (index, item) in [warmup, a, b, c, cooldown].enumerated() {
            frames[item.id] = CGRect(x: 0, y: CGFloat(index) * 110, width: 300, height: 100)
        }
        // Still within its own slot: nothing.
        #expect(draft.blockToSwap(dragging: a.id, centre: 170, frames: frames) == nil)
        // Past the middle of the next one (b: midY 270): swap down with b.
        #expect(draft.blockToSwap(dragging: a.id, centre: 280, frames: frames) == b.id)
        // Far down, past b and c: the nearest passed one is c.
        #expect(draft.blockToSwap(dragging: a.id, centre: 390, frames: frames) == c.id)
        // Upwards: c dragged above b's middle swaps with b.
        #expect(draft.blockToSwap(dragging: c.id, centre: 260, frames: frames) == b.id)
        // Past the cool-down or above the warm-up: pinned blocks are never a target.
        #expect(draft.blockToSwap(dragging: c.id, centre: 520, frames: frames) == nil)
        #expect(draft.blockToSwap(dragging: a.id, centre: 40, frames: frames) == nil)
        // Unknown block: nothing.
        #expect(draft.blockToSwap(dragging: UUID(), centre: 100, frames: frames) == nil)
    }

    // MARK: Recorded steps (MVP2-146)

    /// Warm-up, an open run, three sprint-and-recovery repetitions, a cool-down: nine steps.
    private func sprintWorkout() -> [WorkoutBlock] {
        [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(300))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .open)]),
            WorkoutBlock(
                steps: [WorkoutStep(kind: .work, goal: .time(8)), WorkoutStep(kind: .recovery, goal: .time(300))],
                repetitions: 3
            ),
            WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(300))]),
        ]
    }

    private func recorded(seconds: Double, distance: Double?, heartRate: Double?) -> ActivityStep {
        ActivityStep(
            block: 0, repetition: 0, step: 0, start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: seconds), distanceMeters: distance, averageHeartRateBPM: heartRate
        )
    }

    @Test("with recorded steps a repeating block is one card per repetition, each with its own figures, and every step is numbered once")
    func repetitionsExpanded() {
        let steps = (0..<9).map { index in recorded(seconds: Double(index + 1) * 10, distance: Double(index) * 100, heartRate: 140 + Double(index)) }

        let cards = WorkoutBlockCard.cards(for: sprintWorkout(), actuals: steps, distanceSystem: .metric)

        // Warm-up, open run, then three repetitions, then the cool-down.
        #expect(cards.count == 6)
        #expect(cards.map(\.repetitionNumber) == [nil, nil, 1, 2, 3, nil])
        #expect(cards.map(\.id).count == Set(cards.map(\.id)).count)
        #expect(cards.flatMap(\.steps).map(\.id) == Array(0..<9))
        // Each repetition's recovery has its own figures: planned step 3 for the first, 5 for the second.
        #expect(cards[2].steps[1].actual?.averageHeartRate == "143")
        #expect(cards[3].steps[1].actual?.averageHeartRate == "145")
    }

    @Test("each card with a recorded step gets that step's position, to highlight its span; none without positions")
    func recordedStepIDs() {
        let blocks = [WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(300))]), WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(600))])]
        let first = recorded(seconds: 300, distance: 800, heartRate: 110)
        let second = recorded(seconds: 600, distance: 1700, heartRate: 150)

        let withIDs = WorkoutBlockCard.cards(for: blocks, actuals: [first, second], recordedIDs: [first: 0, second: 1], distanceSystem: .metric)
        let without = WorkoutBlockCard.cards(for: blocks, actuals: [first, second], distanceSystem: .metric)

        #expect(withIDs.flatMap(\.steps).map(\.recordedStepID) == [0, 1])
        #expect(without.flatMap(\.steps).allSatisfy { $0.recordedStepID == nil })
        // A planned step nobody recorded has nothing to highlight.
        let skipped = WorkoutBlockCard.cards(for: blocks, actuals: [first, nil], recordedIDs: [first: 0], distanceSystem: .metric)
        #expect(skipped.flatMap(\.steps).map(\.recordedStepID) == [0, nil])
    }

    @Test("a planned step with no recorded step is marked not recorded, the others carry their figures")
    func skippedStepNotRecorded() {
        var steps: [ActivityStep?] = (0..<9).map { _ in recorded(seconds: 60, distance: 200, heartRate: 150) }
        steps[4] = nil  // the second sprint

        let cards = WorkoutBlockCard.cards(for: sprintWorkout(), actuals: steps, distanceSystem: .metric)

        #expect(cards[3].steps[0].isNotRecorded)  // repetition 2, step 0
        #expect(cards[3].steps[0].actual == nil)
        #expect(!cards[2].steps[0].isNotRecorded)
        #expect(cards[2].steps[0].actual != nil)
    }

    @Test("a step's figures are written as the Watch recorded them: time, distance, average heart rate and pace per kilometre")
    func actualFigures() {
        // The long run's 10 km step: 65:22, 9993.82 m, average 2.29042 beats a second.
        let step = ActivityStep(
            block: 1, repetition: 0, step: 0, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3922),
            distanceMeters: 9993.82, averageHeartRateBPM: 137.4252, wasGoalMet: true
        )

        let actual = WorkoutBlockCard.actual(for: step, distanceSystem: .metric)

        #expect(actual.duration == "1:05:22")
        #expect(actual.distance == "9.99 km")
        #expect(actual.averageHeartRate == "137")
        #expect(actual.averagePace == "6:32 /km")
        #expect(actual.wasGoalMet == true)
    }

    @Test("VoiceOver reads a step's figures as phrases, with the pace spoken per kilometre")
    func spokenFigures() {
        let step = ActivityStep(
            block: 1, repetition: 0, step: 0, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3922),
            distanceMeters: 9993.82, averageHeartRateBPM: 137
        )

        let spoken = WorkoutBlockCard.actual(for: step, distanceSystem: .metric).spokenText

        #expect(spoken == ["recorded 1:05:22", "9.99 km", "average heart rate 137", "average pace 6:32 per km"])
        #expect(WorkoutBlockCard.actual(for: recorded(seconds: 60, distance: nil, heartRate: nil)).spokenText == ["recorded 1:00"])
    }

    @Test("a step with no distance or heart rate leaves those out instead of showing zero")
    func missingFiguresLeftOut() {
        let actual = WorkoutBlockCard.actual(for: recorded(seconds: 472, distance: nil, heartRate: nil), distanceSystem: .metric)

        #expect(actual.duration == "7:52")
        #expect(actual.distance == nil)
        #expect(actual.averageHeartRate == nil)
        #expect(actual.averagePace == nil)
    }

    @Test("distances and paces follow the unit system: meters under a kilometre, miles with a pace per mile")
    func unitSystems() {
        #expect(WorkoutBlockCard.actualDistanceText(801.65, in: .metric) == "802 m")
        #expect(WorkoutBlockCard.actualDistanceText(9993.82, in: .metric) == "9.99 km")
        #expect(WorkoutBlockCard.actualDistanceText(5000, in: .imperial) == "3.11 mi")
        #expect(WorkoutBlockCard.actualDistanceText(150, in: .imperial) == "164 yd")
        #expect(WorkoutBlockCard.paceText(secondsPerKilometer: 392.4, in: .metric) == "6:32 /km")
        #expect(WorkoutBlockCard.paceText(secondsPerKilometer: 392.4, in: .imperial) == "10:32 /mi")
        #expect(WorkoutBlockCard.durationText(59.6) == "1:00")
    }
}
