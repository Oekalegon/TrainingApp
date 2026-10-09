import SwiftUI
import TrainingCore

/// A step opened for editing in place (after the Fitness app's creator): its role, what ends it, the
/// value, the zone it aims for and a delete row, inside the step's card.
struct WorkoutTemplateStepInlineEditor: View {
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
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: step.kind.symbolName)
                        .font(.headline)
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
            .accessibilityLabel("Step type")
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
struct WorkoutRepeatInlineEditor: View {
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
