import SwiftUI
import TrainingCore
import UniformTypeIdentifiers

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
            Text("Drag a step or repeat to reorder it; the warm-up stays first and the cool-down last, if you have them. A duration, distance or repeat count can be a parameter: it becomes a slider when you plan the workout. Touch and hold a step in a repeat to move or remove it.")
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

    /// A step or repeat between the warm-up and the cool-down: draggable onto another one, unless one
    /// of its steps is open for editing (dragging would fight with its fields).
    private func movableBlockCard(_ block: WorkoutTemplateDraft.Block) -> some View {
        let isOpen = block.steps.contains { $0.id == expandedStepID } || expandedRepeatID == block.id
        return blockCard(block, firstNumber: firstStepNumber(of: block))
            .modifier(BlockReorder(blockID: block.id, isDraggable: !isOpen) { sourceID in
                withAnimation(.snappy) { viewModel.moveBlock(id: sourceID, toPositionOf: block.id) }
            })
    }

    @ViewBuilder
    private func blockCard(_ block: WorkoutTemplateDraft.Block, firstNumber: Int) -> some View {
        let draft = viewModel.draft
        let isGroup = block.steps.count > 1 || block.repetitions != .fixed(1)
        let cards = block.steps.enumerated().map { draft.card(for: $1, number: firstNumber + $0) }
        if isGroup {
            WorkoutRepeatCard(steps: cards) {
                VStack(spacing: 0) {
                    Button { toggleRepeat(block.id) } label: {
                        WorkoutRepeatHeader(count: draft.repetitionsText(block))
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

/// A step opened for editing in place (after the Fitness app's creator): its role, what ends it, the
/// value, the zone it aims for and a delete row, inside the step's card.
private struct WorkoutTemplateStepInlineEditor: View {
    let viewModel: WorkoutTemplateEditorViewModel
    @Binding var step: WorkoutTemplateDraft.Step
    let card: WorkoutStepCard
    let onCollapse: () -> Void
    let onDelete: () -> Void

    /// Whether the duration or distance is open to edit its value or parameter. Editing anything else
    /// in the step closes it; touching it, or switching it between fixed and parameter, opens it.
    @State private var isValueExpanded = false

    private enum GoalKind: Hashable { case time, distance, open }

    private var goalKind: Binding<GoalKind> {
        Binding {
            switch step.goal {
            case .time: .time
            case .distance: .distance
            case .open: .open
            }
        } set: { kind in
            switch kind {
            case .time: if case .time = step.goal {} else { step.goal = .time(.fixed(10)) }
            case .distance: if case .distance = step.goal {} else { step.goal = .distance(.fixed(1000)) }
            case .open: step.goal = .open
            }
        }
    }

    private var zone: Binding<Int> {
        Binding {
            switch step.target {
            case .zone(let zone): zone
            case .none: 0
            case .preserved: -1
            }
        } set: { zone in
            step.target = zone == 0 ? .none : .zone(zone)
        }
    }

    private var timeSource: Binding<WorkoutTemplateDraft.Source> {
        Binding {
            if case .time(let source) = step.goal { source } else { .fixed(10) }
        } set: { step.goal = .time($0) }
    }

    private var distanceSource: Binding<WorkoutTemplateDraft.Source> {
        Binding {
            if case .distance(let source) = step.goal { source } else { .fixed(1000) }
        } set: { step.goal = .distance($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onCollapse) {
                HStack(spacing: 12) {
                    Image(systemName: step.kind.symbolName)
                        .font(.title3)
                        .foregroundStyle(card.end.tint)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    Text(step.kind.displayName)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.up")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(step.kind.displayName), editing")
            .accessibilityHint("Collapses this step")
            Divider()
            kindRow
            Divider()
            row {
                LabeledContent("Goal Type") {
                    Picker("Goal Type", selection: goalKind) {
                        Text("Time").tag(GoalKind.time)
                        Text("Distance").tag(GoalKind.distance)
                        Text("Open").tag(GoalKind.open)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            switch step.goal {
            case .time:
                Divider()
                SourceEditor(
                    viewModel: viewModel, title: "Duration", source: timeSource, unit: .minutes,
                    suggestedName: "\(step.kind.displayName) duration", isExpanded: $isValueExpanded
                )
            case .distance:
                Divider()
                SourceEditor(
                    viewModel: viewModel, title: "Distance", source: distanceSource, unit: .meters,
                    suggestedName: "\(step.kind.displayName) distance", isExpanded: $isValueExpanded
                )
            case .open:
                EmptyView()
            }
            Divider()
            row {
                if case .preserved = step.target {
                    LabeledContent("Target", value: "Custom target")
                } else {
                    LabeledContent("Target") {
                        Picker("Target", selection: zone) {
                            Text("None").tag(0)
                            ForEach(HeartRateZone.allCases, id: \.rawValue) { zone in
                                Text("HR Zone \(zone.rawValue) · \(zone.displayName)").tag(zone.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete Step", systemImage: "trash")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .onChange(of: step.kind) { isValueExpanded = false }
        .onChange(of: step.target) { isValueExpanded = false }
        .onChange(of: goalKind.wrappedValue) { isValueExpanded = false }
    }

    /// Work and recovery are a two-way switch, as in the Fitness app; a warm-up or cool-down, which
    /// aren't either, pick from all four.
    @ViewBuilder
    private var kindRow: some View {
        if step.kind == .work || step.kind == .recovery {
            Picker("Step", selection: $step.kind) {
                Text(StepKind.work.displayName).tag(StepKind.work)
                Text(StepKind.recovery.displayName).tag(StepKind.recovery)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        } else {
            row {
                LabeledContent("Step") {
                    // A warm-up or cool-down can become a work or recovery step, but a step can't become
                    // one: they open and close the workout, and only exist there.
                    Picker("Step", selection: $step.kind) {
                        ForEach([step.kind, .work, .recovery], id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
    }
}

/// A repeat opened for editing in place, below its header, like an open step: how often its steps
/// run (fixed or a parameter) and a delete row.
private struct WorkoutRepeatInlineEditor: View {
    let viewModel: WorkoutTemplateEditorViewModel
    @Binding var block: WorkoutTemplateDraft.Block
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SourceEditor(
                viewModel: viewModel, title: "Repeats", source: $block.repetitions, unit: .count,
                suggestedName: "Repeats", isExpanded: $isDetailExpanded
            )
            WorkoutCardDivider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete Repeat", systemImage: "trash")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Open to start with, so the value is shown as soon as the repeat is.
    @State private var isDetailExpanded = true
}

/// A value that is either a fixed number or a parameter of the template (MVP2-140): the athlete turns
/// it into a parameter right where it is. The row reads "Fixed" or "Parameter"; open, it shows the
/// fixed value or the parameter's name, default value and range, smaller and on a lighter background.
/// Closed, it shows a one-line summary instead.
private struct SourceEditor: View {
    @Bindable var viewModel: WorkoutTemplateEditorViewModel
    let title: String
    @Binding var source: WorkoutTemplateDraft.Source
    let unit: ParameterUnit
    /// The name a parameter made here starts with, e.g. "Recovery duration".
    let suggestedName: String
    /// Whether the details are showing; set by the screen that holds the editor, which also closes it
    /// when the athlete edits something else.
    @Binding var isExpanded: Bool

    private enum Choice: Hashable {
        case fixed
        case parameter
    }

    private var choice: Binding<Choice> {
        Binding {
            if case .parameter = source { .parameter } else { .fixed }
        } set: { newChoice in
            switch (newChoice, source) {
            case (.fixed, .parameter(let current)):
                if let parameter = viewModel.draft.parameters.first(where: { $0.id == current }) {
                    source = .fixed(parameter.defaultValue)
                }
            case (.parameter, .fixed(let value)):
                // Starts from the fixed value, so nothing changes until the athlete edits it.
                source = .parameter(viewModel.addParameter(unit: unit, name: suggestedName, defaultValue: value))
            default:
                break
            }
            // What this value no longer uses would only be a slider that does nothing.
            viewModel.pruneUnusedParameters()
            withAnimation(.snappy) { isExpanded = true }
        }
    }

    private var fixedValue: Binding<Double> {
        Binding {
            if case .fixed(let value) = source { value } else { 0 }
        } set: { source = .fixed($0) }
    }

    private func parameterBinding(_ id: UUID) -> Binding<WorkoutTemplateDraft.Parameter>? {
        guard let index = viewModel.draft.parameters.firstIndex(where: { $0.id == id }) else { return nil }
        return $viewModel.draft.parameters[index]
    }

    /// One line for the closed row: the value, or the parameter's name, default and range.
    private var summary: String {
        switch source {
        case .fixed(let value):
            return WorkoutTemplateDraft.valueText(value, unit: unit)
        case .parameter(let id):
            guard let parameter = viewModel.draft.parameters.first(where: { $0.id == id }) else { return "" }
            let low = WorkoutTemplateDraft.valueText(parameter.lowerBound, unit: unit)
            let high = WorkoutTemplateDraft.valueText(parameter.upperBound, unit: unit)
            return "\(parameter.name) · \(WorkoutTemplateDraft.valueText(parameter.defaultValue, unit: unit)) (\(low)–\(high))"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(.snappy) { isExpanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        if !isExpanded {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(isExpanded ? "Collapses the details" : "Shows the details")
                Picker(title, selection: choice) {
                    Text("Fixed").tag(Choice.fixed)
                    Text("Parameter").tag(Choice.parameter)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                // No animation here: switching inserts and removes the rows below, and the menu's label
                // otherwise slid to the edge for a moment.
                .transaction { $0.animation = nil }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            if isExpanded {
                VStack(spacing: 8) {
                    switch source {
                    case .fixed:
                        LabeledContent("Value") { NumberField(label: title, value: fixedValue, unit: unit) }
                    case .parameter(let id):
                        if let parameter = parameterBinding(id) {
                            ParameterFields(parameter: parameter)
                        }
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(isExpanded ? Color.primary.opacity(0.06) : Color.clear)
    }
}

/// A parameter's name, default value and range, in the unit it sets.
private struct ParameterFields: View {
    @Binding var parameter: WorkoutTemplateDraft.Parameter

    var body: some View {
        VStack(spacing: 8) {
            LabeledContent("Name") {
                TextField("Name", text: $parameter.name)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Default Value") { NumberField(label: "Default value", value: $parameter.defaultValue, unit: parameter.unit) }
            LabeledContent("Minimum Value") { NumberField(label: "Minimum value", value: $parameter.lowerBound, unit: parameter.unit) }
            LabeledContent("Maximum Value") { NumberField(label: "Maximum value", value: $parameter.upperBound, unit: parameter.unit) }
        }
    }
}

/// A number field with its unit beside it.
private struct NumberField: View {
    /// What the field sets, read by VoiceOver together with the unit.
    let label: String
    @Binding var value: Double
    let unit: ParameterUnit

    /// The field shows at most three decimals, and a text field can write what it shows back when it
    /// loses focus: 8 seconds (0.1333 minutes) would become 0.133 without the athlete typing anything,
    /// altering the template and counting as a change. A difference below what the field can show is
    /// ignored.
    private var guardedValue: Binding<Double> {
        Binding {
            value
        } set: { newValue in
            if abs(newValue - value) >= 0.0005 { value = newValue }
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField("", value: guardedValue, format: .number)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(unit == .count ? .numberPad : .decimalPad)
                #endif
                .frame(maxWidth: 90)
                .accessibilityLabel("\(label), \(unit.spokenName)")
            Text(unit.shortName)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

private extension ParameterUnit {
    var symbolName: String {
        switch self {
        case .minutes: "timer"
        case .meters: "ruler"
        case .count: "repeat"
        }
    }

    /// The unit as VoiceOver says it.
    var spokenName: String {
        switch self {
        case .minutes: "minutes"
        case .meters: "metres"
        case .count: "times"
        }
    }

    /// The unit beside a number field, as the editor measures it (durations in minutes).
    var shortName: String {
        switch self {
        case .minutes: "min"
        case .meters: "m"
        case .count: "×"
        }
    }
}

/// What a dragged block carries: its id, within this editor.
private struct BlockDragItem: Codable, Transferable {
    let blockID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// Makes a block card draggable and a place to drop another block, to reorder the steps.
private struct BlockReorder: ViewModifier {
    let blockID: UUID
    /// `false` while one of the block's steps is open for editing.
    let isDraggable: Bool
    /// Called with the id of the block dropped on this one.
    let onDrop: (UUID) -> Void

    func body(content: Content) -> some View {
        Group {
            if isDraggable {
                content.draggable(BlockDragItem(blockID: blockID))
            } else {
                content
            }
        }
        .dropDestination(for: BlockDragItem.self) { items, _ in
            guard let source = items.first, source.blockID != blockID else { return false }
            onDrop(source.blockID)
            return true
        }
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
