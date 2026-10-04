import SwiftUI
import TrainingCore

/// The app's top-level screen (design doc §2.0): a bottom tab bar switching between the week view
/// ("Week") and the read-only athlete account screen ("Athlete") — replacing the week view's
/// former "Athlete" toolbar button + sheet.
///
/// Owns the single `WeekViewModel` for the app's lifetime so both tabs share it: `WeekView` reads
/// it directly, and `AthleteView` reads it via `WeekViewModel.athleteViewModel` — that coupling is
/// why `WeekViewModel` is constructed once here rather than inside `WeekView` itself.
///
/// Also puts the next 7 days of planned workouts on the Watch each time the app becomes active
/// (MVP2-55, ``WatchScheduleSync``).
public struct AppTabView: View {
    @State private var viewModel: WeekViewModel
    @Environment(\.scenePhase) private var scenePhase
    private let watchSync: WatchScheduleSync?

    /// - Parameters:
    ///   - model: The app's training model.
    ///   - refresher: Imports activities from HealthKit.
    ///   - watchSync: Run on launch and every time the app becomes active again; `nil` skips it.
    public init(model: TrainingModel, refresher: any ActivityRefreshing, watchSync: WatchScheduleSync? = nil) {
        _viewModel = State(initialValue: WeekViewModel(model: model, refresher: refresher, watchSync: watchSync))
        self.watchSync = watchSync
    }

    public var body: some View {
        // Read once per render, not once for the badge and again for AthleteView's own copy:
        // `TrainingModel.overlapAdvice` reruns `ActivityOverlapChecker.findOverlaps(in:)` on every
        // access (its own doc comment asks SwiftUI `body` callers to cache it), and
        // `overlapReviewItems` derives from exactly that.
        let overlapReviewItems = viewModel.overlapReviewItems

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
                overlapReviewItems: overlapReviewItems,
                athleteTimeZone: viewModel.athleteTimeZone,
                activityDetailViewModel: { viewModel.activityDetailViewModel(for: $0) },
                onResolveOverlap: { await viewModel.resolveOverlap(deleting: $0) },
                onDeleteActivity: { await viewModel.deleteActivity($0) },
                onJoinActivities: { await viewModel.joinActivities($0, with: $1) },
                onUnjoinActivity: { await viewModel.unjoinActivity($0) },
                loadJoinedComponents: { await viewModel.joinedComponents(of: $0) },
                onLinkPlan: { await viewModel.linkActivity($0, toPlan: $1) },
                onUnlinkPlan: { await viewModel.unlinkActivity($0) }
            )
            .tabItem {
                Label("Athlete", systemImage: "person.circle")
            }
            // Same live count `OverlapWarningBanner` shows on the Athlete screen itself (MVP1-67)
            // — both update together whenever an overlap is resolved, since they read the same
            // `WeekViewModel.overlapReviewItems`. `.badge(0)` hides the badge on its own, so no
            // extra `nil`-vs-count branch is needed here.
            .badge(overlapReviewItems.count)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            watchSync?.requestSync()
        }
    }
}
