import SwiftUI
import TrainingCore

/// A short label for a guardrail finding's ``PlanRule`` — `TrainingCore` has no opinion on display
/// strings, same reasoning as `Sport+Display.swift`.
private extension PlanRule {
    var displayName: String {
        switch self {
        case .ctlRamp: "Fitness ramping up fast"
        case .atlToCTLRatio: "Fatigue-to-fitness ratio"
        case .tsbBand: "Form (TSB) out of range"
        case .monotony: "Monotony"
        case .strain: "Strain"
        case .raceDayTSB: "Form on race day"
        case .recoveryMicro: "Recovery week load"
        case .buildProgression: "Build week progression"
        case .mesoProgress: "Fitness gain this block"
        case .taperShape: "Taper shape"
        case .consecutiveLoad: "Consecutive load without recovery"
        }
    }
}

private extension Severity {
    var tintColor: Color {
        switch self {
        case .info: .secondary
        case .warning: .orange
        case .risk: .red
        }
    }
}

/// The "Create Planned Workout" sheet (MVP2-15, design doc): pick a `WorkoutTemplate`, adjust its
/// parameters with a live expected-load preview, see non-blocking guardrail warnings for the
/// hypothetical addition, then save. Own `NavigationStack`/no explicit close button, matching
/// `WeekView`'s `.sheet(item: $selectedActivity)` convention.
struct PlannedWorkoutSheet: View {
    @Bindable var viewModel: PlannedWorkoutSheetViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingSaveError = false

    private static let loadFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
    private static let dayRangeFormat = Date.FormatStyle.dateTime.month(.abbreviated).day()

    var body: some View {
        NavigationStack {
            Form {
                Section("Template") {
                    Picker("Template", selection: $viewModel.selectedTemplate) {
                        Text("Select a template").tag(nil as WorkoutTemplate?)
                        ForEach(viewModel.templates) { template in
                            Text(template.name).tag(template as WorkoutTemplate?)
                        }
                    }
                    TextField("Name", text: $viewModel.workoutName)
                    DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
                }

                if let selectedTemplate = viewModel.selectedTemplate {
                    if !selectedTemplate.parameters.isEmpty {
                        Section("Parameters") {
                            ForEach(selectedTemplate.parameters) { parameter in
                                ParameterRow(
                                    parameter: parameter,
                                    value: Binding(
                                        get: { viewModel.parameterValues[parameter.key] ?? parameter.defaultValue },
                                        set: { viewModel.setParameterValue($0, forKey: parameter.key) }
                                    )
                                )
                            }
                        }
                    }

                    Section("Expected Load") {
                        if let expectedLoad = viewModel.expectedLoad {
                            HStack {
                                Image(systemName: TrainingMetricKind.load.icon)
                                Text("\(expectedLoad.value.formatted(Self.loadFormat)) TRIMP")
                            }
                        } else {
                            Text("Not available")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !viewModel.guardrailSummaries.isEmpty {
                        Section("Guardrail Warnings") {
                            ForEach(viewModel.guardrailSummaries) { summary in
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(summary.rule.displayName)
                                        if summary.dayCount > 1 {
                                            Text("\(summary.firstDay.formatted(Self.dayRangeFormat)) – \(summary.lastDay.formatted(Self.dayRangeFormat)) · \(summary.dayCount) days")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text(summary.firstDay.formatted(Self.dayRangeFormat))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                } icon: {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                }
                                .foregroundStyle(summary.severity.tintColor)
                            }
                        }
                    } else if let guardrailDiagnostic = viewModel.guardrailDiagnostic {
                        Section("Guardrail Warnings") {
                            Text(guardrailDiagnostic)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Planned Workout")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await viewModel.save() {
                                dismiss()
                            } else {
                                isShowingSaveError = true
                            }
                        }
                    }
                    .disabled(viewModel.selectedTemplate == nil || viewModel.isSaving)
                }
            }
            .alert("Couldn't Save Workout", isPresented: $isShowingSaveError, presenting: viewModel.saveError) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }
}

/// One template parameter's label plus a slider bound to its current value, ranged/formatted per
/// `ParameterUnit`.
private struct ParameterRow: View {
    let parameter: WorkoutTemplateParameter
    @Binding var value: Double

    private var range: ClosedRange<Double> {
        parameter.range ?? (parameter.defaultValue / 2)...(parameter.defaultValue * 2)
    }

    private var formattedValue: String {
        switch parameter.unit {
        case .minutes:
            Duration.seconds(value).formatted(.time(pattern: .minuteSecond))
        case .meters:
            Measurement(value: value, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated))
        case .count:
            value.formatted(.number.precision(.fractionLength(0)))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(parameter.name)
                Spacer()
                Text(formattedValue)
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}
