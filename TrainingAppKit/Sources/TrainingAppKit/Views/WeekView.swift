import SwiftUI
import TrainingCore
#if os(iOS)
import UIKit
#endif

/// The app's single top-level screen (design doc §2.1): a 3-week CTL/ATL/TSB chart centered on
/// the displayed week, that week's activities/plans below it, swipe-to-navigate between weeks,
/// a "Today" toolbar button, and pull-to-refresh import.
public struct WeekView: View {
    @State private var viewModel: WeekViewModel
    @State private var isShowingAthlete = false
    /// Horizontal offset applied to `weekContent` while a swipe is in progress, so the current
    /// week visibly tracks the finger during the drag instead of only reacting once it ends.
    /// Animated back to 0 on release — either after committing to a week change (see
    /// `completeSwipe(direction:)`) or snapping back when the drag didn't clear the threshold.
    @State private var dragOffset: CGFloat = 0

    private static let swipeThreshold: CGFloat = 60
    private static let weekChangeAnimation: Animation = .easeInOut(duration: 0.25)
    /// How far `dragOffset` slides during `completeSwipe(direction:)`'s exit animation — far enough
    /// to clear any device width so the current week is fully off-screen before the content swap
    /// underneath it happens, so that swap is never visible.
    private static var swipeExitDistance: CGFloat {
        #if os(iOS)
        UIScreen.main.bounds.width
        #else
        800 // TrainingAppKit also builds for macOS (tests/local `swift build`); WeekView never
            // actually runs there, so this value is unreachable at runtime.
        #endif
    }

    public init(model: TrainingModel, refresher: any ActivityRefreshing) {
        _viewModel = State(initialValue: WeekViewModel(model: model, refresher: refresher))
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.hasNoActivities {
                    EmptyStateView(isConnecting: viewModel.isRefreshing) {
                        Task { await viewModel.connectHealthData() }
                    }
                    .transition(.opacity)
                } else {
                    // `.id` keyed on the displayed week forces SwiftUI to treat each week as a
                    // distinct view rather than diffing the List in place — without it, `.transition`
                    // never animates anything, since there'd be no insert/remove for it to apply to.
                    // Next/previous week's motion comes entirely from `dragOffset`, animated in
                    // `completeSwipe(goingForward:)`; this `.opacity` transition only ever fires
                    // for "Today", which has no drag to follow.
                    weekContent
                        .id(viewModel.displayedWeekStart)
                        .transition(.opacity)
                }
            }
            // Covers the empty-state -> week-content swap once `hasNoActivities` flips (e.g. after
            // "Connect Health Data" completes): that happens asynchronously, well after the button's
            // own `Task` returns, so there's no synchronous call site to wrap in `withAnimation` the
            // way the week-navigation methods below do it -- animating on the value change itself is
            // the only way to catch it. Scoped to just this value so it can't interfere with the
            // explicit `withAnimation` calls `goToNextWeek()`/`goToPreviousWeek()`/`goToToday()` make
            // for `displayedWeekStart` changes.
            .animation(Self.weekChangeAnimation, value: viewModel.hasNoActivities)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Today", systemImage: "calendar") {
                        goToToday()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Athlete", systemImage: "person.circle") {
                        isShowingAthlete = true
                    }
                }
            }
            .task(id: viewModel.displayedWeekStart) {
                await viewModel.load()
            }
            .navigationDestination(for: Activity.self) { activity in
                ActivityDetailView(viewModel: viewModel.activityDetailViewModel(for: activity))
            }
            .sheet(isPresented: $isShowingAthlete) {
                AthleteView(viewModel: viewModel.athleteViewModel)
            }
        }
    }

    private var weekContent: some View {
        List {
            Section {
                FitnessChartView(metrics: viewModel.chartMetrics)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            ForEach(viewModel.weekDates, id: \.self) { day in
                DayActivitiesSection(
                    day: day,
                    activities: viewModel.activities(on: day),
                    plans: viewModel.plans(on: day),
                    workoutName: { viewModel.workout(for: $0)?.name },
                    timeZone: viewModel.athleteTimeZone
                )
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .refreshable {
            await viewModel.refresh()
        }
        .offset(x: dragOffset)
        // `.simultaneousGesture`, not `.gesture`/`.highPriorityGesture` — either of those would
        // claim the touch ahead of List's own scroll recognizer and break vertical scrolling.
        // Running alongside it and only moving content once the horizontal component clearly
        // dominates keeps both usable, at the cost of an occasional false negative on a fast
        // diagonal swipe — acceptable for MVP 1. A low `minimumDistance` (rather than gating all
        // the way to `swipeThreshold`) is what makes the drag feel like it's tracking the finger
        // from near the start of the gesture, not just reacting once it's released.
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in handleSwipeChanged(value) }
                .onEnded { value in handleSwipeEnd(value) }
        )
    }

    private func handleSwipeChanged(_ value: DragGesture.Value) {
        guard abs(value.translation.width) > abs(value.translation.height) else { return }
        dragOffset = value.translation.width
    }

    private func handleSwipeEnd(_ value: DragGesture.Value) {
        guard abs(value.translation.width) > abs(value.translation.height) else { return }
        if value.translation.width < -Self.swipeThreshold {
            completeSwipe(goingForward: true)
        } else if value.translation.width > Self.swipeThreshold {
            completeSwipe(goingForward: false)
        } else {
            // Didn't clear the threshold -- spring back to the current week rather than committing.
            withAnimation(Self.weekChangeAnimation) {
                dragOffset = 0
            }
        }
    }

    /// Finishes a swipe that cleared `swipeThreshold`: animates `dragOffset` the rest of the way
    /// off-screen so the current week visibly continues in the direction it was already being
    /// dragged, then — once that's done — advances `viewModel` and resets `dragOffset` to 0 in the
    /// same (non-animated) beat. That reset is invisible: the outgoing content is already fully
    /// off-screen, and the incoming week's `weekContent` is a fresh, `.id`-keyed instance that
    /// starts at `dragOffset`'s current value (0) — i.e. already in place, not sliding from
    /// off-screen a second time.
    private func completeSwipe(goingForward: Bool) {
        withAnimation(Self.weekChangeAnimation) {
            dragOffset = goingForward ? -Self.swipeExitDistance : Self.swipeExitDistance
        } completion: {
            dragOffset = 0
            if goingForward {
                viewModel.goToNextWeek()
            } else {
                viewModel.goToPreviousWeek()
            }
        }
    }

    /// Jumps to the week containing today. No natural left/right direction (today could be
    /// either side of the displayed week) and no drag to follow, so this just cross-fades.
    private func goToToday() {
        withAnimation(Self.weekChangeAnimation) {
            viewModel.goToToday()
        }
    }
}
