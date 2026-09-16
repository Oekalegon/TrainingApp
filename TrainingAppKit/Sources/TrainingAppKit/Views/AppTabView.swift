import SwiftUI
import TrainingCore

/// The app's top-level screen (design doc §2.0): a bottom tab bar switching between the week view
/// ("Week") and the read-only athlete account screen ("Athlete") — replacing the week view's
/// former "Athlete" toolbar button + sheet.
///
/// Owns the single `WeekViewModel` for the app's lifetime so both tabs share it: `WeekView` reads
/// it directly, and `AthleteView` reads it via `WeekViewModel.athleteViewModel` — that coupling is
/// why `WeekViewModel` is constructed once here rather than inside `WeekView` itself.
public struct AppTabView: View {
    @State private var viewModel: WeekViewModel

    public init(model: TrainingModel, refresher: any ActivityRefreshing) {
        _viewModel = State(initialValue: WeekViewModel(model: model, refresher: refresher))
    }

    public var body: some View {
        TabView {
            WeekView(viewModel: viewModel)
                .tabItem {
                    Label("Week", systemImage: "calendar")
                }

            AthleteView(
                viewModel: viewModel.athleteViewModel,
                isResyncing: viewModel.isResyncing,
                onResync: { Task { await viewModel.resyncActivities() } },
                isDeduplicating: viewModel.isDeduplicating,
                onDeduplicate: { Task { await viewModel.deduplicateActivities() } },
                overlapReviewItems: viewModel.overlapReviewItems,
                athleteTimeZone: viewModel.athleteTimeZone,
                activityDetailViewModel: { viewModel.activityDetailViewModel(for: $0) },
                onResolveOverlap: { await viewModel.resolveOverlap(deleting: $0) },
                onDeleteActivity: { await viewModel.deleteActivity($0) }
            )
            .tabItem {
                Label("Athlete", systemImage: "person.circle")
            }
            // Same live count `OverlapWarningBanner` shows on the Athlete screen itself (MVP1-67)
            // — both update together whenever an overlap is resolved, since they read the same
            // `WeekViewModel.overlapReviewItems`. `.badge(0)` hides the badge on its own, so no
            // extra `nil`-vs-count branch is needed here.
            .badge(viewModel.overlapReviewItems.count)
        }
    }
}
