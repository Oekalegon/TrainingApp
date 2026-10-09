import SwiftUI
import TrainingCore

/// The Library tab (MVP2-21, design doc §2.4): the workout templates the athlete can plan, grouped
/// by sport. Each row shows the template's default title and how often it's planned; tapping it
/// pushes ``WorkoutTemplateDetailView``, whose "Plan This Workout" button opens the planned-workout
/// sheet with the template already picked. The "+" button opens the Structured Workout creator
/// (MVP2-140) for a template of the athlete's own. MVP5's plan builder will live in this tab too.
struct WorkoutLibraryView: View {
    let viewModel: WorkoutLibraryViewModel
    /// The creator's view model, made when "+" is tapped and kept while its sheet is up, so a
    /// re-render doesn't reset the fields (as for ``WorkoutTemplateDetailView``'s planner).
    @State private var editor: WorkoutTemplateEditorViewModel?

    var body: some View {
        NavigationStack {
            WorkoutLibraryList(viewModel: viewModel)
                .navigationTitle("Library")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            editor = viewModel.makeEditorForNewTemplate()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("New Workout Template")
                    }
                }
                .sheet(item: $editor) { editor in
                    WorkoutTemplateEditorSheet(viewModel: editor)
                }
        }
    }
}

/// Every template, grouped by sport, each pushing ``WorkoutTemplateDetailView``.
private struct WorkoutLibraryList: View {
    let viewModel: WorkoutLibraryViewModel
    /// The row a swipe asked to delete, until the athlete confirms.
    @State private var pendingDelete: WorkoutLibraryViewModel.Entry?

    var body: some View {
        List {
            if let loadError = viewModel.loadError {
                Text(loadError)
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.sections()) { section in
                Section(section.sport.displayName) {
                    ForEach(section.entries) { entry in
                        NavigationLink(value: TemplateRoute(id: entry.id)) {
                            WorkoutTemplateRow(entry: entry)
                        }
                        .swipeActions(edge: .trailing) {
                            if entry.isCustom {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    pendingDelete = entry
                                }
                            }
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // By id, not by entry: the detail reads its entry live, so a plan saved from it updates
        // the counts there too.
        .navigationDestination(for: TemplateRoute.self) { route in
            WorkoutTemplateDetailView(viewModel: viewModel, templateID: route.id)
        }
        // Each time the tab appears: plans made on the week view since count too.
        .task { await viewModel.reload() }
        .confirmationDialog(
            "Delete this workout template?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible, presenting: pendingDelete
        ) { entry in
            Button("Delete Workout Template", role: .destructive) {
                Task { await viewModel.deleteTemplate(id: entry.id) }
            }
        } message: { entry in
            Text(WorkoutTemplateDetailView.deleteMessage(planCount: entry.planCount))
        }
        .alert("Couldn't Delete Workout Template", isPresented: Binding(
            get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } }
        ), presenting: viewModel.actionError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }
}

/// One template's row: its sport symbol, name, default title and how often it's planned. Also
/// used for the search tab's template results.
struct WorkoutTemplateRow: View {
    let entry: WorkoutLibraryViewModel.Entry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.template.sport.symbolName)
                .font(.title3)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.template.name)
                    .font(.body)
                Text(entry.defaultTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if entry.isCustom {
                    Text("Custom")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tint)
                }
                if entry.planCount > 0 {
                    Text(WorkoutTemplateDetailView.planCountText(entry.planCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A template's detail screen in the Library tab (MVP2-21): its parameters with their defaults and
/// ranges, its steps at the default values, the estimated load, how it's used in the plan, and a
/// "Plan This Workout" button that opens ``PlannedWorkoutSheet`` with the template picked.
struct WorkoutTemplateDetailView: View {
    let viewModel: WorkoutLibraryViewModel
    let templateID: UUID
    /// The planned-workout sheet's view model, created once when the button is tapped and kept for
    /// as long as the sheet is up — built inside the `.sheet` closure instead, a re-render would
    /// reset its sliders (same reasoning as ``PlannedWorkoutDetailSheet``'s editor).
    @State private var planner: PlannedWorkoutSheetViewModel?
    /// The creator's view model for Edit or Duplicate, kept while its sheet is up, like ``planner``.
    @State private var editor: WorkoutTemplateEditorViewModel?
    @State private var isConfirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    private static let loadFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))

    /// What the delete confirmation says: plans made from the template stay either way.
    static func deleteMessage(planCount: Int) -> String {
        planCount == 0
            ? "This removes the workout template from your library."
            : "It leaves your library, but the plans already made from it stay in your calendar and keep their parameters."
    }

    static func planCountText(_ count: Int) -> String {
        count == 1 ? "Planned once" : "Planned \(count) times"
    }

    private var entry: WorkoutLibraryViewModel.Entry? {
        viewModel.entries().first { $0.id == templateID }
    }

    private func dateText(_ date: Date) -> String {
        var format = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()
        format.timeZone = viewModel.timeZone
        return date.formatted(format)
    }

    var body: some View {
        // Read once: each read works out every template's entry.
        let entry = self.entry
        Form {
            if let entry {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: entry.template.sport.symbolName)
                            .font(.title2)
                            .frame(width: 32)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.template.name)
                                .font(.headline)
                            Text(entry.template.sport.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !entry.template.parameters.isEmpty {
                    Section {
                        ForEach(entry.template.parameters) { parameter in
                            LabeledContent(parameter.name) {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(parameter.formatted(parameter.defaultValue))
                                    if let range = parameter.range {
                                        let low = parameter.formatted(range.lowerBound)
                                        let high = parameter.formatted(range.upperBound)
                                        Text("\(low) – \(high)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            // Read as a range, not as two clock times.
                                            .accessibilityLabel("from \(low) to \(high)")
                                    }
                                }
                            }
                        }
                    } header: {
                        Label("Parameters", systemImage: WorkoutBlockCard.parameterSymbol)
                    } footer: {
                        Text("Defaults, with the range you can choose from when planning.")
                    }
                }

                if !entry.blockCards.isEmpty {
                    Section("Steps") {
                        WorkoutStepListSpacerRow()
                        WorkoutStepCardList(blocks: entry.blockCards)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        WorkoutStepListSpacerRow()
                    }
                }

                if let load = entry.expectedLoad {
                    Section {
                        LabeledContent("Load") {
                            HStack(spacing: 4) {
                                Image(systemName: TrainingMetricKind.load.icon)
                                // Always the estimator's figure (MVP2-8).
                                let text = "\(load.formatted(Self.loadFormat)) TRIMP"
                                Text(EstimateMarker.text(text, isEstimated: true))
                                    .accessibilityLabel(EstimateMarker.spoken(text, isEstimated: true))
                            }
                        }
                    } header: {
                        Text("Expected")
                    } footer: {
                        Text("Estimated at the default values from your heart-rate zones.")
                    }
                }

                Section("In Your Plan") {
                    if entry.planCount == 0 {
                        Text("Not planned yet")
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Used", value: Self.planCountText(entry.planCount))
                        if let next = entry.nextPlannedDate {
                            LabeledContent("Next", value: dateText(next))
                        }
                    }
                }

                Section {
                    Button {
                        planner = viewModel.makePlanner(for: entry.template)
                    } label: {
                        Label("Plan This Workout", systemImage: "calendar.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                }

                // A built-in workout can't be changed, only copied; "Duplicate" is the way to
                // start from one.
                Section {
                    // Centred, like "Plan This Workout" above.
                    if entry.isCustom {
                        Button {
                            editor = viewModel.makeEditor(for: entry.template)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    Button {
                        editor = viewModel.makeEditorDuplicating(entry.template)
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                            .frame(maxWidth: .infinity)
                    }
                    if entry.isCustom {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                } footer: {
                    if !entry.isCustom {
                        Text("Built-in workout templates can't be changed. Duplicate one to make your own version.")
                    }
                }
            } else {
                Text("This workout template is no longer in the library.")
                    .foregroundStyle(.secondary)
            }
        }
        // The step list's spacer rows are one point high (``WorkoutStepListSpacerRow``).
        .environment(\.defaultMinListRowHeight, 1)
        .navigationTitle(entry?.template.name ?? "Workout Template")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: Binding(get: { planner != nil }, set: { if !$0 { planner = nil } })) {
            if let planner {
                PlannedWorkoutSheet(viewModel: planner)
            }
        }
        .sheet(item: $editor) { editor in
            WorkoutTemplateEditorSheet(viewModel: editor)
        }
        .confirmationDialog(
            "Delete this workout template?", isPresented: $isConfirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete Workout Template", role: .destructive) {
                Task {
                    // Stay on the screen when it failed: the library shows why.
                    if await viewModel.deleteTemplate(id: templateID) != nil {
                        dismiss()
                    }
                }
            }
        } message: {
            Text(Self.deleteMessage(planCount: entry?.planCount ?? 0))
        }
    }
}
