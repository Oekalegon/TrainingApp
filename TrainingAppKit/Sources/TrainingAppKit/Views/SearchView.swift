import SwiftUI
import TrainingCore

/// The search tab (MVP2-21, design doc §2.5): instant results across workout templates, planned
/// workouts and activities as the athlete types in the tab bar's search field, which `AppTabView`
/// attaches with `.searchable` and shows from every tab. A template pushes its library detail; a
/// planned workout opens its detail sheet and an activity its detail, as on the week view, once
/// ``SearchViewModel`` has loaded the week view's model around the result's day.
struct SearchView: View {
    let viewModel: SearchViewModel
    /// Builds the planned-workout and activity detail sheets and runs their actions, exactly as the
    /// week view does, so a result's sheet behaves like its card's. Passed whole rather than as
    /// closures (unlike `AthleteView`) because both sheets need it.
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
                            NavigationLink(value: TemplateRoute(id: entry.id)) {
                                WorkoutTemplateRow(entry: entry)
                            }
                        }
                    }
                }
                if !results.plans.isEmpty {
                    Section("Planned Workouts") {
                        ForEach(results.plans) { result in
                            Button {
                                Task {
                                    if let plan = await viewModel.open(result) { selectedPlan = plan }
                                }
                            } label: {
                                ResultRow(
                                    symbolName: result.sport?.symbolName ?? "calendar",
                                    title: result.name,
                                    subtitle: planSubtitle(result)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isOpening)
                        }
                    }
                }
                if !results.activities.isEmpty {
                    Section("Activities") {
                        ForEach(results.activities) { result in
                            Button {
                                Task {
                                    if let activity = await viewModel.openActivity(id: result.id) {
                                        selectedActivity = activity
                                    }
                                }
                            } label: {
                                ResultRow(
                                    symbolName: result.sport.symbolName,
                                    title: result.planName ?? result.sport.displayName,
                                    subtitle: activitySubtitle(result)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isOpening)
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
            .navigationDestination(for: TemplateRoute.self) { route in
                WorkoutTemplateDetailView(viewModel: viewModel.library, templateID: route.id)
            }
            // Each time the tab appears, so plans and activities added since are found.
            .task { await viewModel.reload() }
            // Closing a sheet that changed something reloads, so an edited or deleted plan or
            // activity shows that way in the results afterwards.
            .sheet(item: $selectedPlan, onDismiss: { Task { await viewModel.reloadIfChanged() } }) { plan in
                PlannedWorkoutDetailSheet(viewModel: planDetailViewModel(for: plan))
            }
            .sheet(item: $selectedActivity, onDismiss: { Task { await viewModel.reloadIfChanged() } }) { activity in
                // Its own NavigationStack, as on the week view and Athlete tab. Every action that
                // can change the results marks them for a reload.
                NavigationStack {
                    ActivityDetailView(
                        viewModel: weekViewModel.activityDetailViewModel(for: activity),
                        onResolveOverlap: { id in
                            await weekViewModel.resolveOverlap(deleting: id)
                            viewModel.markChanged()
                        },
                        onDelete: {
                            await weekViewModel.deleteActivity(activity)
                            viewModel.markChanged()
                        },
                        onJoin: { other in
                            let joined = await weekViewModel.joinActivities(activity, with: other)
                            if joined { viewModel.markChanged() }
                            return joined
                        },
                        onUnjoin: {
                            let unjoined = await weekViewModel.unjoinActivity(activity)
                            if unjoined { viewModel.markChanged() }
                            return unjoined
                        },
                        loadComponents: { await weekViewModel.joinedComponents(of: activity) },
                        onLinkPlan: {
                            let linked = await weekViewModel.linkActivity(activity, toPlan: $0)
                            if linked { viewModel.markChanged() }
                            return linked
                        },
                        onUnlinkPlan: {
                            let unlinked = await weekViewModel.unlinkActivity(activity)
                            if unlinked { viewModel.markChanged() }
                            return unlinked
                        }
                    )
                }
            }
            .alert(
                "Couldn't Open Activity",
                isPresented: Binding(
                    get: { viewModel.activityError != nil },
                    set: { if !$0 { viewModel.clearActivityError() } }
                ),
                presenting: viewModel.activityError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    /// The plan detail's view model, as the week view builds it, also marking the results for a
    /// reload when the plan is edited or deleted.
    private func planDetailViewModel(for plan: PlannedActivity) -> PlannedWorkoutDetailViewModel {
        let detail = weekViewModel.plannedWorkoutDetailViewModel(for: plan)
        let syncWatch = detail.onPlansChanged
        detail.onPlansChanged = { [viewModel] in
            syncWatch?()
            viewModel.markChanged()
        }
        return detail
    }

    private func planSubtitle(_ result: SearchViewModel.PlanResult) -> String {
        switch viewModel.status(of: result) {
        case .upcoming: dateText(result.plan.date)
        case .done: dateText(result.plan.date) + " · Done"
        case .missed: dateText(result.plan.date) + " · Missed"
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
