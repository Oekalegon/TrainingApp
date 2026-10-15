import SwiftUI
import TrainingCore

/// A value that is either a fixed number or a parameter of the template (MVP2-140): the athlete turns
/// it into a parameter right where it is. The row reads "Fixed" or "Parameter"; open, it shows the
/// fixed value or the parameter's name, default value and range, smaller and on a lighter background.
/// Closed, it shows a one-line summary instead.
struct SourceEditor: View {
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
            return WorkoutTemplateDraft.valueText(value, unit: unit, distanceSystem: viewModel.distanceSystem)
        case .parameter(let id):
            guard let parameter = viewModel.draft.parameters.first(where: { $0.id == id }) else { return "" }
            let low = WorkoutTemplateDraft.valueText(parameter.lowerBound, unit: unit, distanceSystem: viewModel.distanceSystem)
            let high = WorkoutTemplateDraft.valueText(parameter.upperBound, unit: unit, distanceSystem: viewModel.distanceSystem)
            return "\(parameter.name) · \(WorkoutTemplateDraft.valueText(parameter.defaultValue, unit: unit, distanceSystem: viewModel.distanceSystem)) (\(low)–\(high))"
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
                // Which step it belongs to, since several can be open in turn.
                .accessibilityLabel("\(suggestedName), fixed or parameter")
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
struct ParameterFields: View {
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
struct NumberField: View {
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
