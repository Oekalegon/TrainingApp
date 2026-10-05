import SwiftUI
import TrainingCore

/// The Library tab (MVP2-21, design doc §2.4): the workout templates the athlete can plan, grouped
/// by sport. Each row shows the template's default title and how often it's planned; tapping it
/// pushes ``WorkoutTemplateDetailView``, whose "Plan This Workout" button opens the planned-workout
/// sheet with the template already picked. MVP5's plan builder will live in this tab too.
struct WorkoutLibraryView: View {
    let viewModel: WorkoutLibraryViewModel

    var body: some View {
        NavigationStack {
            WorkoutLibraryList(viewModel: viewModel, query: "")
                .navigationTitle("Library")
        }
    }
}

/// The search tab (design doc §2.4): instant results from the library as the athlete types in the
/// tab bar's search field, which `AppTabView` attaches with `.searchable`. With an empty field it
/// shows the whole library, like the Library tab.
struct WorkoutSearchView: View {
    let viewModel: WorkoutLibraryViewModel
    let query: String

    var body: some View {
        NavigationStack {
            WorkoutLibraryList(viewModel: viewModel, query: query)
                .navigationTitle("Search")
        }
    }
}

/// The templates matching `query`, grouped by sport, each pushing ``WorkoutTemplateDetailView`` —
/// shared by the Library and search tabs, inside their own `NavigationStack`s.
private struct WorkoutLibraryList: View {
    let viewModel: WorkoutLibraryViewModel
    let query: String

    var body: some View {
        let sections = viewModel.sections(matching: query)
        List {
            if let loadError = viewModel.loadError {
                Text(loadError)
                    .foregroundStyle(.secondary)
            }
            ForEach(sections) { section in
                Section(section.sport.displayName) {
                    ForEach(section.entries) { entry in
                        NavigationLink(value: entry.id) {
                            WorkoutTemplateRow(entry: entry)
                        }
                    }
                }
            }
        }
        .overlay {
            if sections.isEmpty, !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // By id, not by entry: the detail reads its entry live, so a plan saved from it updates
        // the counts there too.
        .navigationDestination(for: UUID.self) { templateID in
            WorkoutTemplateDetailView(viewModel: viewModel, templateID: templateID)
        }
        // Each time the tab appears: plans made on the week view since count too.
        .task { await viewModel.reload() }
    }
}

/// One template's row: its sport symbol, name, default title and how often it's planned.
private struct WorkoutTemplateRow: View {
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
            if entry.planCount > 0 {
                Text(WorkoutTemplateDetailView.planCountText(entry.planCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private static let loadFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))

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
                                        Text("\(parameter.formatted(range.lowerBound)) – \(parameter.formatted(range.upperBound))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Parameters")
                    } footer: {
                        Text("Defaults, with the range you can choose from when planning.")
                    }
                }

                if !entry.stepLines.isEmpty {
                    Section("Steps") {
                        ForEach(Array(entry.stepLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                        }
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
            } else {
                Text("This workout is no longer in the library.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(entry?.template.name ?? "Workout")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: Binding(get: { planner != nil }, set: { if !$0 { planner = nil } })) {
            if let planner {
                PlannedWorkoutSheet(viewModel: planner)
            }
        }
    }
}
