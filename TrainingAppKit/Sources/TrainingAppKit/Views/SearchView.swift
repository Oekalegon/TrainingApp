import SwiftUI
import TrainingCore

/// The search tab (MVP2-21, design doc §2.5): instant results across workout templates, planned
/// workouts and activities as the athlete types in the tab bar's search field, which `AppTabView`
/// attaches with `.searchable` and shows from every tab. A template pushes its library detail; a
/// planned workout opens its detail sheet and an activity its detail, as on the week view.
struct SearchView: View {
    let viewModel: SearchViewModel
    /// For the planned-workout and activity detail sheets, built as the week view builds them.
    let weekViewModel: WeekViewModel
    let query: String

    @State private var selectedPlan: PlannedActivity?
    @State private var selectedActivity: Activity?

    private static let measurementFormat = Measurement<UnitLength>.FormatStyle.measurement(width: .abbreviated)

    var body: some View {
        let results = viewModel.results(for: query)
        NavigationStack {
            List {
                if let loadError = viewModel.loadError {
                    Text(loadError)
                        .foregroundStyle(.secondary)
                }
                if !results.templates.isEmpty {
                    Section("Workout Templates") {
                        ForEach(results.templates) { entry in
                            NavigationLink(value: entry.id) {
                                WorkoutTemplateRow(entry: entry)
                            }
                        }
                    }
                }
                if !results.plans.isEmpty {
                    Section("Planned Workouts") {
                        ForEach(results.plans) { result in
                            Button {
                                selectedPlan = result.plan
                            } label: {
                                ResultRow(
                                    symbolName: result.sport?.symbolName ?? "calendar",
                                    title: result.name,
                                    subtitle: dateText(result.plan.date) + (result.isDone ? " · Done" : "")
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !results.activities.isEmpty {
                    Section("Activities") {
                        ForEach(results.activities) { result in
                            Button {
                                Task { selectedActivity = await viewModel.activity(id: result.id) }
                            } label: {
                                ResultRow(
                                    symbolName: result.sport.symbolName,
                                    title: result.planName ?? result.sport.displayName,
                                    subtitle: activitySubtitle(result)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .overlay {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView(
                        "Search",
                        systemImage: "magnifyingglass",
                        description: Text("Find workout templates, planned workouts and activities.")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Search")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: UUID.self) { templateID in
                WorkoutTemplateDetailView(viewModel: viewModel.library, templateID: templateID)
            }
            // Each time the tab appears, so plans and activities added since are found.
            .task { await viewModel.reload() }
            // A plan edited or deleted in its sheet shows that way in the results afterwards.
            .sheet(item: $selectedPlan, onDismiss: { Task { await viewModel.reload() } }) { plan in
                PlannedWorkoutDetailSheet(viewModel: weekViewModel.plannedWorkoutDetailViewModel(for: plan))
            }
            .sheet(item: $selectedActivity, onDismiss: { Task { await viewModel.reload() } }) { activity in
                // Its own NavigationStack, as on the week view and Athlete tab.
                NavigationStack {
                    ActivityDetailView(
                        viewModel: weekViewModel.activityDetailViewModel(for: activity),
                        onResolveOverlap: { id in await weekViewModel.resolveOverlap(deleting: id) },
                        onDelete: { await weekViewModel.deleteActivity(activity) },
                        onJoin: { other in await weekViewModel.joinActivities(activity, with: other) },
                        onUnjoin: { await weekViewModel.unjoinActivity(activity) },
                        loadComponents: { await weekViewModel.joinedComponents(of: activity) },
                        onLinkPlan: { await weekViewModel.linkActivity(activity, toPlan: $0) },
                        onUnlinkPlan: { await weekViewModel.unlinkActivity(activity) }
                    )
                }
            }
        }
    }

    private func dateText(_ date: Date) -> String {
        var format = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()
        format.timeZone = viewModel.timeZone
        return date.formatted(format)
    }

    private func activitySubtitle(_ result: SearchViewModel.ActivityResult) -> String {
        var parts = [dateText(result.start), Duration.seconds(result.duration).formatted(.time(pattern: .hourMinuteSecond))]
        if let meters = result.distanceMeters, result.sport.isEndurance {
            parts.append(Measurement(value: meters, unit: UnitLength.meters).formatted(Self.measurementFormat))
        }
        return parts.joined(separator: " · ")
    }
}

/// A planned-workout or activity result: sport symbol, title and a secondary line.
private struct ResultRow: View {
    let symbolName: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.title3)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
