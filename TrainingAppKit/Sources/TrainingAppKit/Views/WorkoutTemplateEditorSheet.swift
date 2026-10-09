import SwiftUI
import TrainingCore

/// The Structured Workout creator (MVP2-140, design doc §2.4): a sheet to make a workout template,
/// change one of the athlete's own, or edit a copy of a built-in one. Sections for the name and
/// sport, the parameters the athlete can tune when planning it, and its blocks of steps.
struct WorkoutTemplateEditorSheet: View {
    @Bindable var viewModel: WorkoutTemplateEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingSaveError = false

    var body: some View {
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

                ForEach(Array($viewModel.draft.blocks.enumerated()), id: \.element.id) { index, $block in
                    WorkoutTemplateBlockSection(
                        viewModel: viewModel, block: $block, number: index + 1,
                        parameters: viewModel.draft.parameters
                    )
                }

                Section {
                    Button {
                        viewModel.addBlock()
                    } label: {
                        Label("Add Block", systemImage: "plus")
                    }
                } footer: {
                    Text("A block repeats its steps, e.g. a block of work and recovery repeated 6 times.")
                }

                summarySection
            }
            .navigationTitle(viewModel.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
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
                    .disabled(!viewModel.canSave)
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

    @ViewBuilder
    private var summarySection: some View {
        let issues = viewModel.issues
        if issues.isEmpty {
            if let title = viewModel.defaultTitlePreview {
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
            LabeledContent("Starts at") { NumberField(value: $parameter.defaultValue, unit: parameter.unit) }
            LabeledContent("Lowest") { NumberField(value: $parameter.lowerBound, unit: parameter.unit) }
            LabeledContent("Highest") { NumberField(value: $parameter.upperBound, unit: parameter.unit) }
        }
    }
}

/// One block: how often it repeats, its steps, and buttons to add a step or remove the block.
private struct WorkoutTemplateBlockSection: View {
    let viewModel: WorkoutTemplateEditorViewModel
    @Binding var block: WorkoutTemplateDraft.Block
    let number: Int
    let parameters: [WorkoutTemplateDraft.Parameter]

    var body: some View {
        Section {
            SourceEditor(
                title: "Repeats", source: $block.repetitions, unit: .count,
                parameters: parameters.filter { $0.unit == .count }
            )
            ForEach($block.steps) { $step in
                WorkoutTemplateStepEditor(step: $step, parameters: parameters)
            }
            .onDelete { viewModel.removeSteps(at: $0, fromBlock: block.id) }
            .onMove { viewModel.moveSteps(from: $0, to: $1, inBlock: block.id) }
            Button {
                viewModel.addStep(toBlock: block.id)
            } label: {
                Label("Add Step", systemImage: "plus")
            }
            Button(role: .destructive) {
                viewModel.removeBlock(id: block.id)
            } label: {
                Label("Remove Block", systemImage: "trash")
            }
        } header: {
            Text("Block \(number)")
        }
    }
}

/// One step: its role, what ends it and the zone it aims for.
private struct WorkoutTemplateStepEditor: View {
    @Binding var step: WorkoutTemplateDraft.Step
    let parameters: [WorkoutTemplateDraft.Parameter]

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
        VStack(alignment: .leading, spacing: 4) {
            Picker("Step", selection: $step.kind) {
                ForEach([StepKind.warmup, .work, .recovery, .cooldown], id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            Picker("Ends after", selection: goalKind) {
                Text("Time").tag(GoalKind.time)
                Text("Distance").tag(GoalKind.distance)
                Text("Open").tag(GoalKind.open)
            }
            switch step.goal {
            case .time(let source):
                SourceEditor(
                    title: "Duration", source: timeSource, unit: .minutes,
                    parameters: parameters.filter { $0.unit == .minutes }
                )
                .id(source.isFixed)
            case .distance(let source):
                SourceEditor(
                    title: "Distance", source: distanceSource, unit: .meters,
                    parameters: parameters.filter { $0.unit == .meters }
                )
                .id(source.isFixed)
            case .open:
                EmptyView()
            }
            if case .preserved = step.target {
                LabeledContent("Target", value: "Custom target")
            } else {
                Picker("Target", selection: zone) {
                    Text("None").tag(0)
                    ForEach(HeartRateZone.allCases, id: \.rawValue) { zone in
                        Text("Zone \(zone.rawValue) · \(zone.displayName)").tag(zone.rawValue)
                    }
                }
            }
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
            LabeledContent(title) { NumberField(value: fixedValue, unit: unit) }
        } else {
            Picker(title, selection: parameterID) {
                Text("Fixed").tag(nil as UUID?)
                ForEach(parameters) { parameter in
                    Text(parameter.name).tag(parameter.id as UUID?)
                }
            }
            if case .fixed = source {
                LabeledContent("Value") { NumberField(value: fixedValue, unit: unit) }
            }
        }
    }
}

/// A number field with its unit beside it.
private struct NumberField: View {
    @Binding var value: Double
    let unit: ParameterUnit

    var body: some View {
        HStack(spacing: 4) {
            TextField("", value: $value, format: .number)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(unit == .count ? .numberPad : .decimalPad)
                #endif
                .frame(maxWidth: 90)
            Text(unit.shortName)
                .foregroundStyle(.secondary)
        }
    }
}

private extension WorkoutTemplateDraft.Source {
    var isFixed: Bool {
        if case .fixed = self { true } else { false }
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

    /// The unit beside a number field, as the editor measures it (durations in minutes).
    var shortName: String {
        switch self {
        case .minutes: "min"
        case .meters: "m"
        case .count: "×"
        }
    }
}

private extension StepKind {
    var displayName: String {
        switch self {
        case .warmup: "Warmup"
        case .work: "Work"
        case .recovery: "Recovery"
        case .cooldown: "Cooldown"
        }
    }
}
