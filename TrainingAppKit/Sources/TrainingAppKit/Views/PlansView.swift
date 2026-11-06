import Charts
import SwiftUI
import TrainingCore

/// The list of every training plan with its status,
/// and for each plan activate, archive, duplicate, rename and delete, plus a preview of a draft's
/// projected form against the active plan's. Only the active plan shows in the calendar, the
/// micro-cycle view and on the Watch; the footer says so.
private struct PlansListView: View {
    let viewModel: PlansViewModel
    /// The plan a swipe or menu asked to delete, until the athlete confirms.
    @State private var pendingDelete: PlansViewModel.Entry?
    /// The plan being renamed, with the name typed so far.
    @State private var renaming: PlansViewModel.Entry?
    @State private var newName = ""

    var body: some View {
        List {
            if !viewModel.isAvailable {
                Text("Training plans aren't available in this build.")
                    .foregroundStyle(.secondary)
            } else {
                if let loadError = viewModel.loadError {
                    Text(loadError).foregroundStyle(.secondary)
                }
                if viewModel.entries.isEmpty, viewModel.hasLoaded {
                    ContentUnavailableView(
                        "No Plans Yet", systemImage: "list.bullet.rectangle",
                        description: Text("A plan appears here as soon as you plan a workout.")
                    )
                }
                if viewModel.hasLoaded, !viewModel.entries.isEmpty, !viewModel.entries.contains(where: \.isActive) {
                    Section("Active") {
                        Text("No plan is active, so the calendar and your Apple Watch show no planned workouts. Activate a plan below.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(PlanSection.allCases) { section in
                    let rows = viewModel.entries.filter { section.contains($0.plan.status) }
                    if !rows.isEmpty {
                        Section {
                            ForEach(rows) { entry in
                                NavigationLink(value: PlansView.Destination.plan(entry.id)) {
                                    PlanRow(entry: entry)
                                }
                                .swipeActions(edge: .trailing) {
                                    // The active plan is archived, not deleted, so the calendar isn't emptied by a swipe.
                                    if !entry.isActive {
                                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = entry }
                                            .disabled(!entry.canDelete || viewModel.isWorking)
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    if !entry.isActive {
                                        Button("Activate", systemImage: "checkmark.circle") {
                                            Task { await viewModel.activate(entry) }
                                        }
                                        .tint(.green)
                                        .disabled(viewModel.isWorking)
                                    }
                                }
                                .contextMenu { actions(for: entry) }
                            }
                        } header: {
                            Text(section.title)
                        } footer: {
                            if section == .active {
                                Text("Only the active plan shows in the calendar and the micro-cycle view, counts towards your fitness and form, and is sent to your Apple Watch.")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("All Plans")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .refreshable { await viewModel.reload() }
        .confirmationDialog(
            "Delete this plan?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible, presenting: pendingDelete
        ) { entry in
            Button("Delete Plan", role: .destructive) { Task { await viewModel.delete(entry) } }
        } message: { entry in
            Text("“\(entry.plan.name)” and its \(entry.workoutCount) planned workouts are removed from your account. This can't be undone.")
        }
        .alert("Rename Plan", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let entry = renaming { Task { await viewModel.rename(entry, to: newName) } }
            }
        }
    }

    /// The actions on one plan, as a context menu.
    @ViewBuilder
    private func actions(for entry: PlansViewModel.Entry) -> some View {
        if !entry.isActive {
            Button("Activate", systemImage: "checkmark.circle") { Task { await viewModel.activate(entry) } }
        }
        Button("Rename", systemImage: "pencil") {
            newName = entry.plan.name
            renaming = entry
        }
        Button("Duplicate", systemImage: "plus.square.on.square") { Task { await viewModel.duplicate(entry) } }
        if entry.plan.status != .archived {
            Button("Archive", systemImage: "archivebox") { Task { await viewModel.archive(entry) } }
        }
        if entry.canDelete, !entry.isActive {
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = entry }
        }
    }
}

/// The Plans tab (MVP5-125): opens on the active plan, with a toolbar button for a new plan and one for
/// the list of every plan (active, drafts, archived). Only the active plan shows in the calendar, the
/// micro-cycle view and on the Watch.
struct PlansView: View {
    /// What the tab's stack can show beyond the active plan.
    enum Destination: Hashable {
        case list
        case plan(UUID)
    }

    @State private var viewModel: PlansViewModel
    private let microCycleViewModel: MicroCycleViewModel
    @State private var path: [Destination] = []
    /// The day the add-race sheet is for, while it is shown.
    @State private var addingEntryDate: DayAddDate?
    /// Bumped when a race is added, so an open plan's projection reads it.
    @State private var previewRefresh = 0
    /// The Create Plan wizard (MVP5-146), while it is shown.
    @State private var creatingPlan: CreatingPlan?

    init(microCycleViewModel: MicroCycleViewModel) {
        self.microCycleViewModel = microCycleViewModel
        _viewModel = State(initialValue: microCycleViewModel.plansViewModel())
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !viewModel.isAvailable {
                    ContentUnavailableView("Plans Unavailable", systemImage: "list.bullet.rectangle",
                        description: Text("Training plans aren't available in this build."))
                } else if let active = viewModel.activeEntry {
                    PlanDetailView(viewModel: viewModel, planID: active.id, refreshToken: previewRefresh)
                } else if viewModel.hasLoaded {
                    ContentUnavailableView {
                        Label("No Active Plan", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("No plan is active, so the calendar and your Apple Watch show no planned workouts. Activate a plan from the list, or create one.")
                    } actions: {
                        Button("Show All Plans") { path.append(.list) }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(viewModel.activeEntry?.plan.name ?? "Plans")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if viewModel.isAvailable {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("All Plans", systemImage: "list.bullet") { path.append(.list) }
                        Menu("Add", systemImage: "plus") {
                            Button("New Plan…", systemImage: "list.bullet.rectangle") {
                                creatingPlan = CreatingPlan(viewModel: microCycleViewModel.createPlanViewModel())
                            }
                            .disabled(viewModel.isWorking)
                            Button("Add Race…", systemImage: "flag.checkered") {
                                addingEntryDate = DayAddDate(date: viewModel.today())
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .list: PlansListView(viewModel: viewModel)
                case .plan(let id): PlanDetailView(viewModel: viewModel, planID: id, refreshToken: previewRefresh)
                }
            }
        }
        .task { await viewModel.reload() }
        .sheet(item: $addingEntryDate, onDismiss: {
            previewRefresh += 1
            Task { await viewModel.reload() }
        }) { entryDate in
            AddRaceSheet(viewModel: microCycleViewModel.raceSheetViewModel(date: entryDate.date))
        }
        .sheet(item: $creatingPlan) { creating in
            CreatePlanView(viewModel: creating.viewModel) { plan in
                Task {
                    await viewModel.reload()
                    path.append(.plan(plan.id))
                }
            }
        }
        .alert("Couldn't Change the Plan", isPresented: Binding(
            get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } }
        ), presenting: viewModel.actionError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }
}

/// A Create Plan wizard being shown; identifiable so the sheet can be presented by item.
private struct CreatingPlan: Identifiable {
    let id = UUID()
    let viewModel: CreatePlanViewModel
}

/// The groups the plans are listed in.
private enum PlanSection: CaseIterable, Identifiable {
    case active, drafts, past

    var id: Self { self }

    var title: String {
        switch self {
        case .active: "Active"
        case .drafts: "Drafts"
        case .past: "Archived"
        }
    }

    func contains(_ status: PlanStatus) -> Bool {
        switch self {
        case .active: status == .active
        case .drafts: status == .draft
        case .past: status == .archived || status == .cancelled
        }
    }
}

extension PlanStatus {
    /// The status as shown to the athlete.
    var displayName: String {
        switch self {
        case .draft: "Draft"
        case .active: "Active"
        case .archived: "Archived"
        case .cancelled: "Cancelled"
        }
    }
}

/// One plan's row: its name, status and how many workouts it holds.
private struct PlanRow: View {
    let entry: PlansViewModel.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.plan.name).font(.body)
                if entry.isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                }
            }
            Text(PlanText.summary(of: entry))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.plan.name), \(entry.plan.status.displayName), \(PlanText.summary(of: entry))")
    }
}

/// Text shared by the plan list and its detail screen.
enum PlanText {
    /// "12 workouts · 3 Nov – 21 Dec", or "No workouts".
    static func summary(of entry: PlansViewModel.Entry) -> String {
        guard entry.workoutCount > 0 else { return "No workouts" }
        let count = entry.workoutCount == 1 ? "1 workout" : "\(entry.workoutCount) workouts"
        guard let span = entry.dateSpan else { return count }
        let format = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return "\(count) · \(span.lowerBound.formatted(format)) – \(span.upperBound.formatted(format))"
    }
}
