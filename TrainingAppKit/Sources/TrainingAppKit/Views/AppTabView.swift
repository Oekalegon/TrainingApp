import SwiftUI
import TrainingCore

/// The app's top-level screen (design doc §2.0): a bottom tab bar switching between the week view
/// ("Week"), the workout library ("Library", MVP2-21) and the athlete account screen ("Athlete") —
/// replacing the week view's former "Athlete" toolbar button + sheet — plus a search tab, there from
/// every tab, whose field sits in the tab bar and searches workout templates, planned workouts and
/// activities as the athlete types.
///
/// Owns the single `WeekViewModel` for the app's lifetime so both tabs share it: `WeekView` reads
/// it directly, and `AthleteView` reads it via `WeekViewModel.athleteViewModel` — that coupling is
/// why `WeekViewModel` is constructed once here rather than inside `WeekView` itself.
///
/// Also puts the next 7 days of planned workouts on the Watch each time the app becomes active
/// (MVP2-55, ``WatchScheduleSync``), and opens the Athlete tab's Apple Watch synchronisation screen
/// when the week view's Watch permission banner asks for it (MVP2-117, MVP2-123).
public struct AppTabView: View {
    /// The app's tabs, for `TabView`'s selection.
    private enum AppTab: Hashable {
        case week
        case library
        case athlete
        case search
    }

    @State private var viewModel: WeekViewModel
    /// The Library tab's view model (MVP2-21), kept for the app's lifetime so its plan counts
    /// survive switching tabs.
    @State private var libraryViewModel: WorkoutLibraryViewModel
    /// The search tab's view model (MVP2-21); shares the library's so both show the same counts.
    @State private var searchViewModel: SearchViewModel
    /// The visible tab. Kept so the week view's Watch permission banner (MVP2-117) can open the
    /// Athlete tab; not remembered across launches.
    @State private var selectedTab = AppTab.week
    /// The Athlete tab's pushed screens (MVP2-123), kept here so the Watch permission banner can open
    /// the Apple Watch synchronisation screen directly.
    @State private var athletePath: [AthleteRoute] = []
    /// The tab bar's search field (MVP2-21).
    @State private var searchText = ""
    @Environment(\.scenePhase) private var scenePhase
    private let watchSync: WatchScheduleSync?

    /// - Parameters:
    ///   - model: The app's training model.
    ///   - refresher: Imports activities from HealthKit.
    ///   - watchSync: Run on launch and every time the app becomes active again; `nil` skips it.
    public init(model: TrainingModel, refresher: any ActivityRefreshing, watchSync: WatchScheduleSync? = nil) {
        let viewModel = WeekViewModel(model: model, refresher: refresher, watchSync: watchSync)
        _viewModel = State(initialValue: viewModel)
        let libraryViewModel = viewModel.workoutLibraryViewModel()
        _libraryViewModel = State(initialValue: libraryViewModel)
        _searchViewModel = State(initialValue: viewModel.searchViewModel(library: libraryViewModel))
        self.watchSync = watchSync
    }

    public var body: some View {
        // Read once per render, not once for the badge and again for AthleteView's own copy:
        // `TrainingModel.overlapAdvice` reruns `ActivityOverlapChecker.findOverlaps(in:)` on every
        // access (its own doc comment asks SwiftUI `body` callers to cache it), and
        // `overlapReviewItems` derives from exactly that.
        let overlapReviewItems = viewModel.overlapReviewItems

        TabView(selection: $selectedTab) {
            Tab("Week", systemImage: "calendar", value: AppTab.week) {
                WeekView(viewModel: viewModel, onShowWatchSettings: {
                    athletePath = AthleteRoute.watchSettings
                    selectedTab = .athlete
                })
            }

            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                WorkoutLibraryView(viewModel: libraryViewModel)
            }

            Tab("Athlete", systemImage: "person.circle", value: AppTab.athlete) {
                AthleteView(
                    viewModel: viewModel.athleteViewModel,
                    weekViewModel: viewModel,
                    path: $athletePath,
                    isResyncing: viewModel.isResyncing,
                    onResync: { Task { await viewModel.resyncActivities() } },
                    isDeduplicating: viewModel.isDeduplicating,
                    onDeduplicate: { Task { await viewModel.deduplicateActivities() } },
                    isRefreshing: viewModel.isRefreshing,
                    hasNoActivities: viewModel.hasNoActivities,
                    onImport: { Task { await viewModel.refresh() } },
                    onConnectHealth: { Task { await viewModel.connectHealthData() } },
                    overlapReviewItems: overlapReviewItems,
                    athleteTimeZone: viewModel.athleteTimeZone,
                    activityDetailViewModel: { viewModel.activityDetailViewModel(for: $0) },
                    onResolveOverlap: { await viewModel.resolveOverlap(deleting: $0) },
                    onDeleteActivity: { await viewModel.deleteActivity($0) },
                    onJoinActivities: { await viewModel.joinActivities($0, with: $1) },
                    onUnjoinActivity: { await viewModel.unjoinActivity($0) },
                    loadJoinedComponents: { await viewModel.joinedComponents(of: $0) },
                    onLinkPlan: { await viewModel.linkActivity($0, toPlan: $1) },
                    onUnlinkPlan: { await viewModel.unlinkActivity($0) },
                    watchSync: watchSync
                )
            }
            // Same live count `OverlapWarningBanner` shows on the Athlete screen itself (MVP1-67)
            // — both update together whenever an overlap is resolved, since they read the same
            // `WeekViewModel.overlapReviewItems`. `.badge(0)` hides the badge on its own, so no
            // extra `nil`-vs-count branch is needed here.
            .badge(overlapReviewItems.count)

            // The search role puts this tab apart at the trailing end of the tab bar, on every
            // tab, where it turns into the search field when selected — as in Mail (MVP2-21).
            Tab(value: AppTab.search, role: .search) {
                SearchView(viewModel: searchViewModel, weekViewModel: viewModel, query: searchText)
            }
        }
        .searchable(text: $searchText, prompt: "Workouts and Activities")
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            watchSync?.requestSync()
        }
        // A workout imported in the background (MVP2-121) already synced the Watch; the caches are
        // this view model's own.
        .onReceive(NotificationCenter.default.publisher(for: .trainingAppDidImportWorkouts)) { _ in
            Task { await viewModel.activitiesImportedElsewhere() }
        }
    }
}
