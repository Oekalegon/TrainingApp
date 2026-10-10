import SwiftUI
import TrainingCore

/// The sheet shown when a planned activity's card is tapped (MVP2-38): a read-only summary of the
/// workout — name, sport, date, why it can't go on the Apple Watch if it can't (MVP2-122), expected
/// duration/distance/load (estimates marked with a "~" and a "Forecast"/"Estimate" caption, MVP2-8),
/// the step cards — with a pencil that opens ``PlannedWorkoutSheet`` in
/// edit mode and a Delete button at the bottom behind a confirmation alert. Own `NavigationStack`,
/// icon-only toolbar buttons, matching `PlannedWorkoutSheet`'s conventions.
struct PlannedWorkoutDetailSheet: View {
    @State private var viewModel: PlannedWorkoutDetailViewModel
    @Environment(\.dismiss) private var dismiss
    /// The edit sheet's view model, created once when the pencil is tapped and kept here for as long as
    /// the edit sheet is up. Building it inside the `.sheet` content closure instead would make a
    /// fresh one — with the plan's original parameter values — every time this view's body
    /// re-evaluates, so a slider would jump back right after being dragged.
    @State private var editor: PlannedWorkoutSheetViewModel?
    @State private var isConfirmingDelete = false
    @State private var isShowingDeleteError = false

    /// Kept in `@State` (set once from the initializer) so the view model survives the presenting
    /// `WeekView` re-evaluating its `.sheet(item:)` content — a fresh one each time would drop
    /// `isDeleting`/`deleteError` mid-operation.
    init(viewModel: PlannedWorkoutDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private static let loadFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
    private static let measurementFormat = Measurement<UnitLength>.FormatStyle.measurement(width: .abbreviated)

    private var dateText: String {
        var format = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day().year()
        format.timeZone = viewModel.timeZone
        return viewModel.plan.date.formatted(format)
    }

    var body: some View {
        NavigationStack {
            Form {
                let summary = viewModel.summary
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: summary.sport.symbolName)
                            .font(.title2)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.name ?? "Planned workout")
                                .font(.headline)
                            Text(dateText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MVP2-122: the reason the plan's card shows, spelled out where there's room.
                if let reason = viewModel.watchIncompatibility {
                    Section("Apple Watch") {
                        Label {
                            Text(reason)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // From the summary read above: each read of either runs the forecast.
                let expected = viewModel.expected(from: summary)
                Section {
                    if let duration = expected?.duration {
                        LabeledContent("Duration") {
                            VStack(alignment: .trailing, spacing: 2) {
                                let text = Duration.seconds(duration).formatted(.time(pattern: .hourMinuteSecond))
                                // VoiceOver reads the caption below instead of the "~" (MVP2-8).
                                Text(EstimateMarker.text(text, isEstimated: expected?.isDurationForecast == true))
                                    .accessibilityLabel(text)
                                // Distance and open steps take as long as the athlete's pace makes
                                // them — a forecast, so it says so.
                                if expected?.isDurationForecast == true {
                                    Text("Forecast")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let meters = expected?.distanceMeters {
                        LabeledContent("Distance") {
                            VStack(alignment: .trailing, spacing: 2) {
                                let text = Measurement(value: meters, unit: UnitLength.meters).formatted(Self.measurementFormat)
                                Text(EstimateMarker.text(text, isEstimated: expected?.isDistanceForecast == true))
                                    .accessibilityLabel(text)
                                // A duration-based workout has no distance of its own — this is a
                                // forecast from the athlete's paces, so it says so.
                                if expected?.isDistanceForecast == true {
                                    Text("Forecast")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let load = summary.load {
                        LabeledContent("Load") {
                            VStack(alignment: .trailing, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: TrainingMetricKind.load.icon)
                                    let text = "\(load.formatted(Self.loadFormat)) TRIMP"
                                    Text(EstimateMarker.text(text, isEstimated: summary.isLoadEstimated))
                                        .accessibilityLabel(text)
                                }
                                // The estimator's figure, not one the athlete set (MVP2-8).
                                if summary.isLoadEstimated {
                                    Text("Estimate")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Expected")
                } footer: {
                    if let basis = expected?.basis {
                        Text(basis)
                    }
                }

                let steps = viewModel.stepCards
                if !steps.isEmpty {
                    WorkoutStepCardSection(blocks: steps)
                }

                Section {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Text("Delete Planned Workout")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(viewModel.isDeleting)
                }
            }
            .environment(\.defaultMinListRowHeight, 1)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle("Planned Workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = viewModel.makeEditor()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit")
                }
            }
            .sheet(isPresented: Binding(get: { editor != nil }, set: { if !$0 { editor = nil } })) {
                if let editor {
                    PlannedWorkoutSheet(viewModel: editor)
                }
            }
            .alert("Delete Planned Workout?", isPresented: $isConfirmingDelete) {
                Button("Delete", role: .destructive) {
                    Task {
                        if await viewModel.delete() {
                            dismiss()
                        } else {
                            isShowingDeleteError = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(viewModel.deletionMessage) will be removed from your plan. This can't be undone.")
            }
            .alert("Couldn't Delete Workout", isPresented: $isShowingDeleteError, presenting: viewModel.deleteError) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }
}
