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
    /// The step or block whose own screen is pushed.
    @State private var editingStep: StepRef?
    @State private var editingBlock: BlockRef?

    private struct StepRef: Hashable { let blockID: UUID; let stepID: UUID }
    private struct BlockRef: Hashable { let blockID: UUID }

    private func blockBinding(_ id: UUID) -> Binding<WorkoutTemplateDraft.Block>? {
        guard let index = viewModel.draft.blocks.firstIndex(where: { $0.id == id }) else { return nil }
        return $viewModel.draft.blocks[index]
    }

    private func stepBinding(_ ref: StepRef) -> Binding<WorkoutTemplateDraft.Step>? {
        guard let block = blockBinding(ref.blockID),
              let index = block.wrappedValue.steps.firstIndex(where: { $0.id == ref.stepID }) else { return nil }
        return block.steps[index]
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

                parameterSection

                stepsSection

                summarySection(summary)
            }
            .navigationDestination(item: $editingStep) { ref in
                if let step = stepBinding(ref) {
                    WorkoutTemplateStepForm(
                        viewModel: viewModel, blockID: ref.blockID, step: step, parameters: viewModel.draft.parameters
                    )
                }
            }
            .navigationDestination(item: $editingBlock) { ref in
                if let block = blockBinding(ref.blockID) {
                    WorkoutTemplateBlockForm(viewModel: viewModel, block: block, parameters: viewModel.draft.parameters)
                }
            }
            // Swiping the sheet away would lose a long edit without asking.
            .interactiveDismissDisabled(viewModel.hasChanges)
            .confirmationDialog("Discard your changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
            }
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
            .alert("Couldn't Save Workout", isPresented: $isShowingSaveError, presenting: viewModel.saveError) { _ in
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

    private var parameterSection: some View {
        Section {
            ForEach($viewModel.draft.parameters) { $parameter in
                WorkoutTemplateParameterEditor(parameter: $parameter)
            }
            .onDelete { offsets in
                for id in offsets.map({ viewModel.draft.parameters[$0].id }) {
                    viewModel.removeParameter(id: id)
                }
            }
            Menu {
                Button("Duration", systemImage: "timer") { viewModel.addParameter(unit: .minutes) }
                Button("Distance", systemImage: "ruler") { viewModel.addParameter(unit: .meters) }
                Button("Repeats", systemImage: "repeat") { viewModel.addParameter(unit: .count) }
            } label: {
                Label("Add Parameter", systemImage: "plus")
            }
        } header: {
            Text("Parameters")
        } footer: {
            Text("A parameter becomes a slider when you plan the workout, e.g. the duration of the main set.")
        }
    }

    /// The workout's steps as cards, like the Fitness app's list: tapping a step opens its fields, the
    /// "Repeat" header opens the block's repeats, and "Add Step" / "Add Repeat" are cards of their own.
    private var stepsSection: some View {
        Section {
            VStack(spacing: 10) {
                ForEach(viewModel.draft.blocks) { block in
                    let firstNumber = viewModel.draft.blocks.prefix { $0.id != block.id }.reduce(0) { $0 + $1.steps.count }
                    blockCard(block, firstNumber: firstNumber)
                }
                Button { viewModel.addBlock() } label: {
                    WorkoutAddCardLabel(title: "Add Step", symbolName: "plus")
                }
                .buttonStyle(.plain)
                .cardStyle()
                Button { viewModel.addRepeat() } label: {
                    WorkoutAddCardLabel(title: "Add Repeat", symbolName: "repeat")
                }
                .buttonStyle(.plain)
                .cardStyle()
            }
            .padding(.vertical, 6)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            Text("Steps")
        } footer: {
            Text("Touch and hold a step to move, repeat or remove it.")
        }
    }

    @ViewBuilder
    private func blockCard(_ block: WorkoutTemplateDraft.Block, firstNumber: Int) -> some View {
        let draft = viewModel.draft
        let isGroup = block.steps.count > 1 || block.repetitions != .fixed(1)
        let cards = block.steps.enumerated().map { draft.card(for: $1, number: firstNumber + $0) }
        if isGroup {
            WorkoutRepeatCard(steps: cards) {
                Button { editingBlock = BlockRef(blockID: block.id) } label: {
                    WorkoutRepeatHeader(count: draft.repetitionsText(block))
                }
                .buttonStyle(.plain)
            } stepView: { card in
                stepButton(block: block, card: card, index: card.id - firstNumber)
            } footer: {
                Divider()
                Button { viewModel.addStep(toBlock: block.id) } label: {
                    WorkoutAddCardLabel(title: "Add Step", symbolName: "plus")
                }
                .buttonStyle(.plain)
            }
        } else {
            ForEach(cards) { card in
                stepButton(block: block, card: card, index: card.id - firstNumber).cardStyle()
            }
        }
    }

    private func stepButton(block: WorkoutTemplateDraft.Block, card: WorkoutStepCard, index: Int) -> some View {
        let step = block.steps[index]
        return Button { editingStep = StepRef(blockID: block.id, stepID: step.id) } label: {
            WorkoutStepCardView(step: card)
        }
        .buttonStyle(.plain)
        .contextMenu {
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
            if block.repetitions == .fixed(1), block.steps.count == 1 {
                Button("Repeat", systemImage: "repeat") { viewModel.setRepetitions(2, inBlock: block.id) }
            }
            Button("Remove Step", systemImage: "trash", role: .destructive) {
                viewModel.removeSteps(at: IndexSet(integer: index), fromBlock: block.id)
            }
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

/// One parameter's name, starting value and range, in the unit it sets.
private struct WorkoutTemplateParameterEditor: View {
    @Binding var parameter: WorkoutTemplateDraft.Parameter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: parameter.unit.symbolName)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Name", text: $parameter.name)
            }
            LabeledContent("Starts at") { NumberField(label: "Starts at", value: $parameter.defaultValue, unit: parameter.unit) }
            LabeledContent("Lowest") { NumberField(label: "Lowest", value: $parameter.lowerBound, unit: parameter.unit) }
            LabeledContent("Highest") { NumberField(label: "Highest", value: $parameter.upperBound, unit: parameter.unit) }
        }
    }
}

/// A step's own screen: its role, what ends it and the zone it aims for.
private struct WorkoutTemplateStepForm: View {
    let viewModel: WorkoutTemplateEditorViewModel
    let blockID: UUID
    @Binding var step: WorkoutTemplateDraft.Step
    let parameters: [WorkoutTemplateDraft.Parameter]
    @Environment(\.dismiss) private var dismiss

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

    var body: some View {
        Form {
            Section {
                Picker("Step", selection: $step.kind) {
                    ForEach([StepKind.warmup, .work, .recovery, .cooldown], id: \.self) { kind in
                        Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                    }
                }
                Picker("Ends after", selection: goalKind) {
                    Text("Time").tag(GoalKind.time)
                    Text("Distance").tag(GoalKind.distance)
                    Text("Open").tag(GoalKind.open)
                }
                switch step.goal {
                case .time:
                    SourceEditor(
                        title: "Duration", source: timeSource, unit: .minutes,
                        parameters: parameters.filter { $0.unit == .minutes }
                    )
                case .distance:
                    SourceEditor(
                        title: "Distance", source: distanceSource, unit: .meters,
                        parameters: parameters.filter { $0.unit == .meters }
                    )
                case .open:
                    EmptyView()
                }
                if case .preserved = step.target {
                    LabeledContent("Target", value: "Custom target")
                } else {
                    Picker("Target", selection: zone) {
                        Text("None").tag(0)
                        ForEach(HeartRateZone.allCases, id: \.rawValue) { zone in
                            Text("HR Zone \(zone.rawValue) · \(zone.displayName)").tag(zone.rawValue)
                        }
                    }
                }
            }
            Section {
                Button("Remove Step", systemImage: "trash", role: .destructive) {
                    dismiss()
                    viewModel.removeStep(id: step.id, fromBlock: blockID)
                }
            }
        }
        .navigationTitle(step.kind.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
}

/// A block's own screen: how often its steps repeat, and a way to remove it.
private struct WorkoutTemplateBlockForm: View {
    let viewModel: WorkoutTemplateEditorViewModel
    @Binding var block: WorkoutTemplateDraft.Block
    let parameters: [WorkoutTemplateDraft.Parameter]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                SourceEditor(
                    title: "Repeats", source: $block.repetitions, unit: .count,
                    parameters: parameters.filter { $0.unit == .count }
                )
            } footer: {
                Text("The block's steps run this many times in a row.")
            }
            Section {
                Button("Remove Block", systemImage: "trash", role: .destructive) {
                    dismiss()
                    viewModel.removeBlock(id: block.id)
                }
            }
        }
        .navigationTitle("Repeats")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// A value that's either a fixed number or one of the template's parameters of the same unit.
private struct SourceEditor: View {
    let title: String
    @Binding var source: WorkoutTemplateDraft.Source
    let unit: ParameterUnit
    let parameters: [WorkoutTemplateDraft.Parameter]

    private var parameterID: Binding<UUID?> {
        Binding {
            if case .parameter(let id) = source { id } else { nil }
        } set: { id in
            if let id {
                source = .parameter(id)
            } else if case .parameter(let current) = source,
                      let parameter = parameters.first(where: { $0.id == current }) {
                source = .fixed(parameter.defaultValue)
            }
        }
    }

    private var fixedValue: Binding<Double> {
        Binding {
            if case .fixed(let value) = source { value } else { 0 }
        } set: { source = .fixed($0) }
    }

    var body: some View {
        if parameters.isEmpty {
            LabeledContent(title) { NumberField(label: title, value: fixedValue, unit: unit) }
        } else {
            Picker(title, selection: parameterID) {
                Text("Fixed").tag(nil as UUID?)
                ForEach(parameters) { parameter in
                    Text(parameter.name).tag(parameter.id as UUID?)
                }
            }
            if case .fixed = source {
                LabeledContent("Value") { NumberField(label: title, value: fixedValue, unit: unit) }
            }
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
