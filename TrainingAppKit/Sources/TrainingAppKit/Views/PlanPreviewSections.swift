import Charts
import SwiftUI
import TrainingCore

/// The rest of the Create Plan review (MVP5-121), below the summary: the projected form, the micro-cycles with their
/// workouts, and what activating the plan would replace, with the way to activate it. Reads
/// ``CreatePlanViewModel/details``; the logic is in the view model.
struct PlanPreviewSections: View {
    @Bindable var viewModel: CreatePlanViewModel
    /// Called with the plan once it is stored as the active plan.
    let onActivated: (TrainingPlan) -> Void
    @State private var isConfirming = false

    var body: some View {
        if let note = viewModel.previewNote {
            Section { Label(note, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.orange) }
        }
        if let details = viewModel.details {
            if details.form.count > 1 {
                Section("Projected Form") { FormChart(details: details) }
            }
            Section {
                ForEach(details.micros) { micro in
                    DisclosureGroup {
                        if micro.items.isEmpty {
                            Text("No workouts").foregroundStyle(.secondary)
                        }
                        ForEach(micro.items) { item in
                            LabeledContent(item.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), value: item.title)
                                .font(.subheadline)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(micro.phase) · \(micro.name)")
                            Text("\(micro.dates.lowerBound.formatted(date: .abbreviated, time: .omitted)) to \(micro.dates.upperBound.formatted(date: .abbreviated, time: .omitted)) · \(micro.items.count) workout\(micro.items.count == 1 ? "" : "s")")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } header: {
                Text("Workouts by Micro-Cycle")
            }
            Section {
                if let replacement = details.replacement {
                    Text(Self.replacementText(replacement)).font(.subheadline)
                    if !replacement.items.isEmpty {
                        DisclosureGroup("Workouts that stop counting (\(replacement.items.count))") {
                            ForEach(replacement.items) { item in
                                LabeledContent(item.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), value: item.title)
                                    .font(.subheadline)
                            }
                        }
                    }
                } else {
                    Text("No plan is active, so activating this one replaces nothing.").font(.subheadline)
                }
                if !viewModel.isAcceptable {
                    Toggle("I accept the risks above", isOn: $viewModel.acceptsRisks)
                }
                Button("Activate Plan…", systemImage: "checkmark.circle") { isConfirming = true }
                    .disabled(viewModel.isBusy || !viewModel.canActivate || viewModel.problem(in: .review) != nil)
                    .confirmationDialog("Activate this plan?", isPresented: $isConfirming, titleVisibility: .visible) {
                        Button("Activate Plan") {
                            Task { if let plan = await viewModel.commit(activate: true) { onActivated(plan) } }
                        }
                    } message: {
                        Text(details.replacement.map(Self.consequenceText) ?? "No plan is active, so nothing is replaced.")
                    }
            } header: {
                Text("Activate")
            } footer: {
                Text("Create Draft keeps your calendar as it is. Activating makes this the plan your calendar, form and Apple Watch follow.")
            }
        }
    }

    /// What happens to the plan being replaced, without the detail of its workouts: for the confirmation.
    static func consequenceText(_ replacement: PlanPreviewDetails.Replacement) -> String {
        replacement.isFollowed
            ? "\"\(replacement.planName)\" is cancelled and kept as history."
            : "\"\(replacement.planName)\" becomes a draft. Nothing is deleted."
    }

    /// What activating does to the plan being replaced, in a sentence.
    static func replacementText(_ replacement: PlanPreviewDetails.Replacement) -> String {
        let count = replacement.items.count
        let workouts = count == 0 ? "has no upcoming workouts" : "has \(count) upcoming workout\(count == 1 ? "" : "s") that stop\(count == 1 ? "s" : "") counting"
        let fate = replacement.isFollowed
            ? "It is cancelled and kept as history, because you have completed workouts in it."
            : "It becomes a draft. Nothing is deleted."
        return "\"\(replacement.planName)\" is active now and \(workouts). \(fate)"
    }
}

/// The plan's fitness (CTL) and form (TSB) over its length.
private struct FormChart: View {
    let details: PlanPreviewDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(details.form, id: \.day) { point in
                    LineMark(x: .value("Day", point.day), y: .value("Value", point.ctl), series: .value("Metric", "Fitness"))
                        .foregroundStyle(by: .value("Metric", "Fitness"))
                    LineMark(x: .value("Day", point.day), y: .value("Value", point.tsb), series: .value("Metric", "Form"))
                        .foregroundStyle(by: .value("Metric", "Form"))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
            .frame(height: 180)
            .accessibilityLabel("Projected fitness and form chart")
            .accessibilityValue(summary)
            Text(summary).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        guard let peak = details.peakCTL, let final = details.finalCTL else { return "" }
        var text = "Fitness peaks at \(Int(peak.rounded())) and ends at \(Int(final.rounded()))."
        if let low = details.form.map(\.tsb).min(), let high = details.form.map(\.tsb).max() {
            text += " Form ranges from \(Int(low.rounded())) to \(Int(high.rounded()))."
        }
        return text
    }
}
