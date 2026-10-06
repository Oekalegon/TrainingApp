import SwiftUI
import TrainingCore

/// The Athlete tab (MVP2-123, design doc §2.3): the avatar and name, the live overlap warning, and a
/// settings-style list of groups, each opening its own screen — Personal Information (with Heart
/// Rate Zones and Pace Zones inside it), Connected Services (Apple Health, Apple Watch), Calendar
/// and Developer. The screens it opens edit the profile where the athlete knows better than Health
/// (MVP2-132); this list itself only navigates.
///
/// The `NavigationStack`'s path is owned by `AppTabView` (``path``), so the week view's Watch
/// permission banner can open the Apple Watch synchronisation screen directly
/// (``AthleteRoute/watchSettings``). The overlap warning stays on this list, not inside a group, so
/// it's visible whenever the tab is (MVP1-67).
struct AthleteView: View {
    let viewModel: AthleteViewModel
    /// The week view model the screens' edits go through (MVP2-132).
    let weekViewModel: WeekViewModel
    /// The screens currently pushed, owned by `AppTabView`.
    @Binding var path: [AthleteRoute]
    let isResyncing: Bool
    let onResync: () -> Void
    let isDeduplicating: Bool
    let onDeduplicate: () -> Void
    /// Backs the Apple Health screen: an import is running, no activity was ever imported, and the
    /// two actions it offers.
    let isRefreshing: Bool
    let hasNoActivities: Bool
    let onImport: () -> Void
    let onConnectHealth: () -> Void
    /// Every activity currently worth reviewing for an overlap issue (MVP1-67), live from
    /// `WeekViewModel.overlapReviewItems` — backs both ``OverlapWarningBanner`` (shown just below
    /// the avatar) and the review sheet it opens.
    let overlapReviewItems: [OverlapReviewItem]
    let athleteTimeZone: TimeZone
    let activityDetailViewModel: (Activity) -> ActivityDetailViewModel
    let onResolveOverlap: (UUID) async -> Void
    let onDeleteActivity: (Activity) async -> Void
    /// Join actions for the detail sheet (MVP1-80) — see `ActivityDetailView`.
    let onJoinActivities: (Activity, Activity) async -> Bool
    let onUnjoinActivity: (Activity) async -> Bool
    let loadJoinedComponents: (Activity) async -> [Activity]
    let onLinkPlan: (Activity, UUID) async -> Bool
    let onUnlinkPlan: (Activity) async -> Bool
    /// Backs the Apple Watch screens (MVP2-117); `nil` where WorkoutKit isn't available, which hides
    /// the Apple Watch row.
    let watchSync: WatchScheduleSync?
    /// Whether the overlap-review sheet (MVP1-67), opened by tapping ``OverlapWarningBanner``, is
    /// presented.
    @State private var isShowingOverlapReview = false
    /// Set by a row tap in the overlap-review sheet, then consumed by that sheet's `onDismiss` to
    /// open `selectedActivity`'s own detail sheet — chained this way (rather than presenting the
    /// detail sheet directly from on top of the review sheet) since SwiftUI only reliably supports
    /// one sheet on a view at a time. Same pattern `WeekView` used before this moved here.
    @State private var pendingOverlapActivity: Activity?
    /// The activity currently shown in the detail sheet, or `nil` when none is presented.
    @State private var selectedActivity: Activity?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    VStack(spacing: 8) {
                        AvatarView(initials: viewModel.initials)
                        Text(viewModel.displayName)
                            .font(.title3.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                }

                // Live, not dismissible (MVP1-67) — always visible while any overlap is
                // outstanding, so it can never go stale the way the old post-import banner could.
                if !overlapReviewItems.isEmpty {
                    Section {
                        OverlapWarningBanner(count: overlapReviewItems.count) {
                            isShowingOverlapReview = true
                        }
                    }
                    .listRowBackground(Color.orange.opacity(0.15))
                }

                Section {
                    AthleteRouteRow(route: .personalInformation)
                    AthleteRouteRow(route: .connectedServices)
                    AthleteRouteRow(route: .calendar)
                }

                Section {
                    AthleteRouteRow(route: .developer)
                }
            }
            .navigationTitle("Athlete")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: AthleteRoute.self) { route in
                destination(for: route)
            }
            .sheet(item: $selectedActivity) { activity in
                // Its own NavigationStack: a sheet doesn't inherit the presenting view's
                // navigation bar. Same pattern as WeekView's own activity detail sheet.
                NavigationStack {
                    ActivityDetailView(
                        viewModel: activityDetailViewModel(activity),
                        onResolveOverlap: { id in await onResolveOverlap(id) },
                        onDelete: { await onDeleteActivity(activity) },
                        onJoin: { other in await onJoinActivities(activity, other) },
                        onUnjoin: { await onUnjoinActivity(activity) },
                        loadComponents: { await loadJoinedComponents(activity) },
                        onLinkPlan: { await onLinkPlan(activity, $0) },
                        onUnlinkPlan: { await onUnlinkPlan(activity) }
                    )
                }
            }
            // Opens `pendingOverlapActivity`'s own detail sheet only once this one has actually
            // finished dismissing — see that property's own doc comment for why this two-step
            // handoff, rather than presenting straight from on top of this sheet.
            .sheet(
                isPresented: $isShowingOverlapReview,
                onDismiss: {
                    if let pendingOverlapActivity {
                        selectedActivity = pendingOverlapActivity
                        self.pendingOverlapActivity = nil
                    }
                }
            ) {
                NavigationStack {
                    OverlapReviewView(
                        items: overlapReviewItems,
                        timeZone: athleteTimeZone,
                        onSelect: { activity in
                            pendingOverlapActivity = activity
                            isShowingOverlapReview = false
                        }
                    )
                }
            }
        }
    }

    /// The screen `route` opens.
    @ViewBuilder
    private func destination(for route: AthleteRoute) -> some View {
        switch route {
        case .personalInformation:
            PersonalInformationView(viewModel: viewModel, weekViewModel: weekViewModel)
        case .heartRateZones:
            HeartRateZonesView(viewModel: viewModel, weekViewModel: weekViewModel, showsHealthKitSwitch: !hasNoActivities)
        case .paceZones:
            PaceZonesView(viewModel: viewModel, weekViewModel: weekViewModel)
        case .connectedServices:
            ConnectedServicesView(showsAppleWatch: watchSync != nil)
        case .appleHealth:
            AppleHealthView(
                isRefreshing: isRefreshing, hasNoActivities: hasNoActivities,
                onImport: onImport, onConnect: onConnectHealth
            )
        case .appleWatch:
            AppleWatchView()
        case .synchronisation:
            if let watchSync {
                WatchSynchronisationView(sync: watchSync)
            }
        case .calendar:
            CalendarSettingsView(viewModel: viewModel, weekViewModel: weekViewModel)
        case .developer:
            DeveloperView(
                isResyncing: isResyncing, onResync: onResync,
                isDeduplicating: isDeduplicating, onDeduplicate: onDeduplicate
            )
        }
    }
}

/// A list row that pushes `route`: its icon and title.
struct AthleteRouteRow: View {
    let route: AthleteRoute

    var body: some View {
        NavigationLink(value: route) {
            Label(route.title, systemImage: route.systemImage)
        }
    }
}

struct AvatarView: View {
    let initials: String

    var body: some View {
        Text(initials)
            .font(.title.bold())
            .foregroundStyle(.white)
            .frame(width: 72, height: 72)
            .background(Circle().fill(.blue))
            .accessibilityHidden(true)
    }
}
