import Charts
import SwiftUI
import TrainingCore

/// One plan: its actions and its projected form, against the active plan's when it isn't the active one.
/// The Plans tab opens on the active plan's.
struct PlanDetailView: View {
    let viewModel: PlansViewModel
    let planID: UUID
    /// Bumped by the Plans tab when something the projection reads, such as a race, changed.
    var refreshToken = 0
    @State private var newName = ""
    @State private var isRenaming = false

    var body: some View {
        List {
            if let entry = viewModel.entry(id: planID) {
                Section {
                    LabeledContent("Status", value: entry.plan.status.displayName)
                    LabeledContent("Workouts", value: PlanText.summary(of: entry))
                }
                Section {
                    if !entry.isActive {
                        Button("Make This the Active Plan", systemImage: "checkmark.circle") {
                            Task { await viewModel.activate(entry) }
                        }
                    }
                    Button("Rename…", systemImage: "pencil") {
                        newName = entry.plan.name
                        isRenaming = true
                    }
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        Task { await viewModel.duplicate(entry) }
                    }
                    if entry.plan.status != .archived {
                        Button("Archive", systemImage: "archivebox") { Task { await viewModel.archive(entry) } }
                    }
                }
                .disabled(viewModel.isWorking)
                Section("Projected Form") {
                    PlanPreviewSection(viewModel: viewModel, comparesToActive: !entry.isActive)
                }
            } else {
                Text("This plan no longer exists.").foregroundStyle(.secondary)
            }
        }
        .task(id: viewModel.entry(id: planID).map(planTaskID)) {
            if let entry = viewModel.entry(id: planID) { await viewModel.loadPreview(for: entry) }
        }
        .navigationTitle(viewModel.entry(id: planID)?.plan.name ?? "Plan")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Rename Plan", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let entry = viewModel.entry(id: planID) { Task { await viewModel.rename(entry, to: newName) } }
            }
        }
    }

    /// Re-projects when the plan's workouts or status change.
    private func planTaskID(_ entry: PlansViewModel.Entry) -> String {
        // The active plan's identity and size too: a draft's chart is drawn against it.
        let active = viewModel.activeEntry
        return "\(entry.id)-\(entry.plan.status.rawValue)-\(entry.workoutCount)-\(active?.id.uuidString ?? "")-\(active?.workoutCount ?? 0)-\(refreshToken)"
    }
}

/// The draft's fitness (CTL) and form (TSB) projections beside the active plan's, with the
/// guardrail findings, as a chart and a summary.
private struct PlanPreviewSection: View {
    let viewModel: PlansViewModel
    /// Whether to draw the active plan beside this one; not for the active plan itself.
    let comparesToActive: Bool

    var body: some View {
        if let preview = viewModel.preview {
            VStack(alignment: .leading, spacing: 12) {
                Chart {
                    ForEach(preview.days, id: \.day) { day in
                        LineMark(x: .value("Day", day.day), y: .value("Form", day.draftTSB), series: .value("Plan", "This plan"))
                            .foregroundStyle(by: .value("Plan", "This plan"))
                        if preview.hasActivePlan, comparesToActive {
                            LineMark(x: .value("Day", day.day), y: .value("Form", day.activeTSB), series: .value("Plan", "Active plan"))
                                .foregroundStyle(by: .value("Plan", "Active plan"))
                        }
                    }
                }
                .chartYAxisLabel("Form (TSB)")
                .frame(height: 180)
                .accessibilityLabel("Projected form chart")
                .accessibilityValue(summaryText(preview))
            }
            Text(summaryText(preview)).font(.subheadline).foregroundStyle(.secondary)
            FindingsList(title: "This plan", findings: preview.draftFindings)
            if preview.hasActivePlan, comparesToActive {
                FindingsList(title: "Active plan", findings: preview.activeFindings)
            }
        } else if let message = viewModel.previewMessage {
            Text(message).foregroundStyle(.secondary)
        } else {
            ProgressView().accessibilityLabel("Projecting the plan")
        }
    }

    private func summaryText(_ preview: PlansViewModel.Preview) -> String {
        let draft = "This plan peaks at fitness \(Int(preview.draftPeakCTL.rounded())) and ends at \(Int(preview.draftFinalCTL.rounded()))."
        guard preview.hasActivePlan, comparesToActive else { return draft }
        return draft + " The active plan peaks at \(Int(preview.activePeakCTL.rounded())) and ends at \(Int(preview.activeFinalCTL.rounded()))."
    }
}

/// A plan's guardrail findings, one line per rule with the days it is breached on.
private struct FindingsList: View {
    let title: String
    let findings: [PlanFinding]

    var body: some View {
        let byRule = Dictionary(grouping: findings, by: \.rule)
        if byRule.isEmpty {
            Label("\(title): no guardrail findings", systemImage: "checkmark.seal")
                .font(.subheadline)
        } else {
            ForEach(Array(byRule.keys.sorted { "\($0)" < "\($1)" }), id: \.self) { rule in
                let items = byRule[rule] ?? []
                let worst = items.map(\.severity).max { rank($0) < rank($1) } ?? .info
                Label("\(title): \(rule.displayName) on \(items.count) day\(items.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(worst.tintColor)
            }
        }
    }

    private func rank(_ severity: Severity) -> Int {
        switch severity {
        case .info: 0
        case .warning: 1
        case .risk: 2
        }
    }
}
