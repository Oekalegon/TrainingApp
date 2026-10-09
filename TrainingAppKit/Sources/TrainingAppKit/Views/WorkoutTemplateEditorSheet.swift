import SwiftUI
import TrainingCore

/// The Structured Workout creator (MVP2-140, design doc §2.4): a sheet to make a workout template,
/// change one of the athlete's own, or edit a copy of a built-in one. Sections for the name and
/// sport, the parameters the athlete can tune when planning it, and its blocks of steps.
struct WorkoutTemplateEditorSheet: View {
    @Bindable var viewModel: WorkoutTemplateEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingSaveError = false
    @State private var isConfirmingDiscard = false
    /// The step that is open for editing, if any: tapping a step expands it in place and collapses the
    /// one that was open.
    @State private var expandedStepID: UUID?
    /// The repeat whose repeat count is open for editing, if any. Like the open step, only one thing
    /// is open at a time.
    @State private var expandedRepeatID: UUID?
    /// Where each movable block currently sits on screen, measured as they lay out, so a drag can tell
    /// which neighbour it has passed.
    @State private var blockFrames: [UUID: CGRect] = [:]
    /// The block being dragged, if any.
    @State private var draggingBlockID: UUID?
    /// `true` while a reorder gesture is live; it resets itself if the system cancels the touch, which
    /// `onEnded` never hears about, so a card isn't left lifted.
    @GestureState private var isReorderGestureLive = false
    /// How far below the dragged card's top the finger grabbed it.
    @State private var grabOffset: CGFloat = 0
    /// The finger's vertical position on screen while dragging.
    @State private var dragY: CGFloat = 0

    private func blockBinding(_ id: UUID) -> Binding<WorkoutTemplateDraft.Block>? {
        guard let index = viewModel.draft.blocks.firstIndex(where: { $0.id == id }) else { return nil }
        return $viewModel.draft.blocks[index]
    }

    private func stepBinding(blockID: UUID, stepID: UUID) -> Binding<WorkoutTemplateDraft.Step>? {
        guard let block = blockBinding(blockID),
              let index = block.wrappedValue.steps.firstIndex(where: { $0.id == stepID }) else { return nil }
        return block.steps[index]
    }

    /// Opens `stepID` for editing, closing the other; `nil` closes whichever is open.
    private func expand(_ stepID: UUID?) {
        withAnimation(.snappy) {
            expandedStepID = stepID
            if stepID != nil { expandedRepeatID = nil }
        }
    }

    /// Opens or closes the repeat count of the block `blockID`, closing any open step.
    private func toggleRepeat(_ blockID: UUID) {
        withAnimation(.snappy) {
            expandedRepeatID = expandedRepeatID == blockID ? nil : blockID
            if expandedRepeatID != nil { expandedStepID = nil }
        }
    }

    var body: some View {
        let summary = viewModel.summary
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Name", text: $viewModel.draft.name)
                    Picker("Sport", selection: $viewModel.draft.sport) {
                        ForEach(sports, id: \.self) { sport in
                            Label(sport.displayName, systemImage: sport.symbolName).tag(sport)
                        }
                    }
                }

                stepsSection

                summarySection(summary)
            }
            // Swiping the sheet away would lose a long edit without asking.
            .interactiveDismissDisabled(viewModel.hasChanges)
            .confirmationDialog("Discard your changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
            }
            // The step list's spacer rows are one point high (``WorkoutStepListSpacerRow``).
            .environment(\.defaultMinListRowHeight, 1)
            .navigationTitle(viewModel.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if viewModel.hasChanges {
                            isConfirmingDiscard = true
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await viewModel.save() {
                                dismiss()
                            } else if viewModel.saveError != nil {
                                isShowingSaveError = true
                            }
                        }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Save")
                    .disabled(!summary.issues.isEmpty || viewModel.isSaving)
                }
            }
            .alert("Couldn't Save Workout Template", isPresented: $isShowingSaveError, presenting: viewModel.saveError) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    /// The sports a workout can be for: the named ones, plus the draft's own when it's another.
    private var sports: [Sport] {
        let named: [Sport] = [
            .running, .indoorRunning, .outdoorRunning, .cycling, .swimming, .walking, .hiking, .rowing,
            .strength, .coreStrengthTraining
        ]
        return named.contains(viewModel.draft.sport) ? named : named + [viewModel.draft.sport]
    }

    /// The workout's steps as cards, like the Fitness app's list: tapping a step opens its fields, the
    /// "Repeat" header opens the block's repeats, and "Add Step" / "Add Repeat" are cards of their own.
    private var stepsSection: some View {
        Section {
            WorkoutStepListSpacerRow()
            // The warm-up stays on top and the cool-down at the bottom; the steps and repeats between
            // them can be dragged, and new ones are added between them. Each card is a list row of its
            // own: with all of them in one row, a drag lifted the whole list as a single picture.
            if let leading = viewModel.draft.leadingBlockIndex {
                pinnedBlockCard(viewModel.draft.blocks[leading]).stepListRow()
            } else {
                // Removed: a card to put it back.
                Button { expand(viewModel.addWarmup()) } label: {
                    WorkoutAddCardLabel(title: "Add Warm-up", symbolName: StepKind.warmup.symbolName)
                }
                .buttonStyle(.plain)
                .cardStyle()
                .stepListRow()
            }
            ForEach(viewModel.draft.blocks[viewModel.draft.movableRange]) { block in
                movableBlockCard(block).stepListRow()
            }
            // One card for both, after the Fitness app's creator.
            VStack(spacing: 0) {
                Button {
                    expand(viewModel.addBlock())
                } label: {
                    WorkoutAddCardLabel(title: "Add Step", symbolName: "plus")
                }
                .buttonStyle(.plain)
                Divider()
                Button {
                    expand(viewModel.addRepeat())
                } label: {
                    WorkoutAddCardLabel(title: "Add Repeat", symbolName: "repeat")
                }
                .buttonStyle(.plain)
            }
            .cardStyle()
            .stepListRow()
            if let trailing = viewModel.draft.trailingBlockIndex {
                pinnedBlockCard(viewModel.draft.blocks[trailing]).stepListRow()
            } else {
                Button { expand(viewModel.addCooldown()) } label: {
                    WorkoutAddCardLabel(title: "Add Cool-down", symbolName: StepKind.cooldown.symbolName)
                }
                .buttonStyle(.plain)
                .cardStyle()
                .stepListRow()
            }
            WorkoutStepListSpacerRow()
        } header: {
            Text("Steps")
        } footer: {
            Text("Touch and hold a step or repeat, then drag it to reorder; the warm-up stays first and the cool-down last, if you have them. A duration, distance or repeat count can be a parameter: it becomes a slider when you plan the workout. Touch and hold a step in a repeat for its move and remove options.")
        }
    }

    /// The position of `block`'s first step among all of the workout's steps, which numbers its cards.
    private func firstStepNumber(of block: WorkoutTemplateDraft.Block) -> Int {
        viewModel.draft.blocks.prefix { $0.id != block.id }.reduce(0) { $0 + $1.steps.count }
    }

    /// The opening warm-up or closing cool-down: a card that doesn't move.
    private func pinnedBlockCard(_ block: WorkoutTemplateDraft.Block) -> some View {
        blockCard(block, firstNumber: firstStepNumber(of: block))
    }

    /// A step or repeat between the warm-up and the cool-down: touch and hold, then drag it over its
    /// neighbours to reorder. Not while one of its steps is open for editing, since dragging would fight
    /// with its fields.
    private func movableBlockCard(_ block: WorkoutTemplateDraft.Block) -> some View {
        let isOpen = block.steps.contains { $0.id == expandedStepID } || expandedRepeatID == block.id
        let isDragging = draggingBlockID == block.id
        let frame = blockFrames[block.id] ?? .zero
        return blockCard(block, firstNumber: firstStepNumber(of: block))
            // The card follows the finger; the layout slot it came from is what `blockFrames` measures.
            .scaleEffect(isDragging ? 1.02 : 1)
            .shadow(color: .black.opacity(isDragging ? 0.25 : 0), radius: 10, y: 4)
            .offset(y: isDragging ? dragY - grabOffset - frame.minY : 0)
            .zIndex(isDragging ? 1 : 0)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: BlockFramePreference.self, value: [block.id: proxy.frame(in: .global)])
                }
            )
            // Only when something moved: every write re-renders the list.
            .onPreferenceChange(BlockFramePreference.self) { frames in
                let merged = blockFrames.merging(frames) { _, new in new }
                if merged != blockFrames { blockFrames = merged }
            }
            .onChange(of: isReorderGestureLive) { _, live in
                if !live, draggingBlockID != nil { withAnimation(.snappy) { draggingBlockID = nil } }
            }
            .accessibilityAction(named: "Move Up") { withAnimation(.snappy) { viewModel.moveBlock(id: block.id, by: -1) } }
            .accessibilityAction(named: "Move Down") { withAnimation(.snappy) { viewModel.moveBlock(id: block.id, by: 1) } }
            // Simultaneous, so the card's own button (which opens the step) and the list's scrolling don't
            // swallow the touch before the long press can lift it.
            .simultaneousGesture(isOpen ? nil : reorderGesture(for: block.id))
    }

    /// Touch and hold, then drag: lifts the card, moves it with the finger and swaps it with each
    /// neighbour the finger passes the middle of.
    private func reorderGesture(for id: UUID) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if draggingBlockID != id {
                    guard let frame = blockFrames[id] else { return }
                    draggingBlockID = id
                    grabOffset = drag.startLocation.y - frame.minY
                    expand(nil)
                }
                dragY = drag.location.y
                reorderIfPassed(id)
            }
            .updating($isReorderGestureLive) { _, live, _ in live = true }
            .onEnded { _ in
                withAnimation(.snappy) { draggingBlockID = nil }
            }
    }

    /// Swaps the dragged block with the neighbour its centre has passed, if any.
    private func reorderIfPassed(_ id: UUID) {
        guard let frame = blockFrames[id] else { return }
        let centre = dragY - grabOffset + frame.height / 2
        if let target = viewModel.draft.blockToSwap(dragging: id, centre: centre, frames: blockFrames) {
            withAnimation(.snappy) { viewModel.moveBlock(id: id, toPositionOf: target) }
        }
    }

    @ViewBuilder
    private func blockCard(_ block: WorkoutTemplateDraft.Block, firstNumber: Int) -> some View {
        let draft = viewModel.draft
        let isGroup = block.steps.count > 1 || block.repetitions != .fixed(1)
        let cards = block.steps.enumerated().map { draft.card(for: $1, number: firstNumber + $0, distanceSystem: viewModel.distanceSystem) }
        if isGroup {
            WorkoutRepeatCard(steps: cards) {
                VStack(spacing: 0) {
                    Button { toggleRepeat(block.id) } label: {
                        WorkoutRepeatHeader(count: draft.repetitionsText(block), parameterName: draft.parameterName(block.repetitions))
                    }
                    .buttonStyle(.plain)
                    if expandedRepeatID == block.id, let binding = blockBinding(block.id) {
                        WorkoutCardDivider()
                        WorkoutRepeatInlineEditor(viewModel: viewModel, block: binding) {
                            withAnimation(.snappy) { expandedRepeatID = nil }
                            viewModel.removeBlock(id: block.id)
                        }
                    }
                }
            } stepView: { card in
                stepRow(block: block, card: card, index: card.id - firstNumber)
            } footer: {
                WorkoutCardDivider()
                Button {
                    viewModel.addStep(toBlock: block.id)
                    expand(viewModel.draft.blocks.first { $0.id == block.id }?.steps.last?.id)
                } label: {
                    WorkoutAddCardLabel(title: "Add Step", symbolName: "plus")
                }
                .buttonStyle(.plain)
            }
        } else {
            ForEach(cards) { card in
                stepRow(block: block, card: card, index: card.id - firstNumber).cardStyle()
            }
        }
    }

    /// A step as its card, or, when it is the open one, its fields in place of the card.
    @ViewBuilder
    private func stepRow(block: WorkoutTemplateDraft.Block, card: WorkoutStepCard, index: Int) -> some View {
        let step = block.steps[index]
        if expandedStepID == step.id, let binding = stepBinding(blockID: block.id, stepID: step.id) {
            WorkoutTemplateStepInlineEditor(
                viewModel: viewModel, step: binding, card: card,
                onCollapse: { expand(nil) },
                onDelete: {
                    expand(nil)
                    viewModel.removeStep(id: step.id, fromBlock: block.id)
                }
            )
        } else {
            stepButton(block: block, card: card, index: index)
        }
    }

    @ViewBuilder
    private func stepButton(block: WorkoutTemplateDraft.Block, card: WorkoutStepCard, index: Int) -> some View {
        let step = block.steps[index]
        let button = Button { expand(step.id) } label: {
            WorkoutStepCardView(step: card)
        }
        .buttonStyle(.plain)
        // A step on its own is dragged, and a touch-and-hold menu would take that gesture, so only the
        // steps inside a repeat have one.
        if block.steps.count > 1 {
            button.contextMenu {
                if index > 0 {
                    Button("Move Up", systemImage: "arrow.up") {
                        viewModel.moveSteps(from: IndexSet(integer: index), to: index - 1, inBlock: block.id)
                    }
                }
                if index < block.steps.count - 1 {
                    Button("Move Down", systemImage: "arrow.down") {
                        viewModel.moveSteps(from: IndexSet(integer: index), to: index + 2, inBlock: block.id)
                    }
                }
                Button("Remove Step", systemImage: "trash", role: .destructive) {
                    viewModel.removeSteps(at: IndexSet(integer: index), fromBlock: block.id)
                }
            }
        } else {
            button
        }
    }

    @ViewBuilder
    private func summarySection(_ summary: WorkoutTemplateEditorViewModel.Summary) -> some View {
        let issues = summary.issues
        if issues.isEmpty {
            if let title = summary.defaultTitle {
                Section {
                    LabeledContent("Default title", value: title)
                } footer: {
                    Text("What a planned workout is called at the default values.")
                }
            }
        } else {
            Section("To Fix") {
                ForEach(issues, id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The on-screen frames of the movable blocks, by id, for the reorder drag.
private struct BlockFramePreference: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private extension View {
    /// Makes a step card a clear, separator-less list row with a little space around it.
    func stepListRow() -> some View {
        listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
