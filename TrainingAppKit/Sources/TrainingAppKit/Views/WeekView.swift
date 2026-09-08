import SwiftUI
import TrainingCore

/// The app's single top-level screen (design doc §2.1): a 3-week CTL/ATL/TSB chart centered on
/// the displayed week, that week's activities/plans below it, swipe-to-navigate between weeks,
/// a "Today" toolbar button, and pull-to-refresh import.
public struct WeekView: View {
    @State private var viewModel: WeekViewModel
    @State private var isShowingAthlete = false
    /// The transition the *next* week change should use — set just before mutating
    /// `viewModel.displayedWeekStart` so it's in place before SwiftUI removes/inserts the
    /// `.id`-keyed `weekContent` below. Slides in the swipe direction for next/previous week;
    /// "Today" (which has no natural left/right direction) just cross-fades.
    @State private var weekTransition: AnyTransition = .opacity

    private static let swipeThreshold: CGFloat = 60
    private static let weekChangeAnimation: Animation = .easeInOut(duration: 0.25)

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
                    weekContent
                        .id(viewModel.displayedWeekStart)
                        .transition(weekTransition)
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
        // `.simultaneousGesture`, not `.gesture`/`.highPriorityGesture` — either of those would
        // claim the touch ahead of List's own scroll recognizer and break vertical scrolling.
        // Running alongside it and only acting in `onEnded` when the horizontal component clearly
        // dominates keeps both usable, at the cost of an occasional false negative on a fast
        // diagonal swipe — acceptable for MVP 1.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in handleSwipeEnd(value) }
        )
    }

    private func handleSwipeEnd(_ value: DragGesture.Value) {
        guard abs(value.translation.width) > abs(value.translation.height) else { return }
        if value.translation.width < -Self.swipeThreshold {
            goToNextWeek()
        } else if value.translation.width > Self.swipeThreshold {
            goToPreviousWeek()
        }
    }

    /// Advances to next week, sliding the new week in from the trailing edge (the natural
    /// direction for a leftward/"forward in time" swipe).
    private func goToNextWeek() {
        weekTransition = .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
        withAnimation(Self.weekChangeAnimation) {
            viewModel.goToNextWeek()
        }
    }

    /// Moves back to the previous week, sliding the new week in from the leading edge.
    private func goToPreviousWeek() {
        weekTransition = .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
        withAnimation(Self.weekChangeAnimation) {
            viewModel.goToPreviousWeek()
        }
    }

    /// Jumps to the week containing today. No natural left/right direction (today could be
    /// either side of the displayed week), so this just cross-fades.
    private func goToToday() {
        weekTransition = .opacity
        withAnimation(Self.weekChangeAnimation) {
            viewModel.goToToday()
        }
    }
}
