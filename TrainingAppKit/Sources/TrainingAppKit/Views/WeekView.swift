import SwiftUI
import TrainingCore

/// The app's single top-level screen (design doc §2.1): a 3-week CTL/ATL/TSB chart centered on
/// the displayed week, that week's activities/plans below it, swipe-to-navigate between weeks,
/// a "Today" toolbar button, and pull-to-refresh import.
public struct WeekView: View {
    @State private var viewModel: WeekViewModel
    @State private var isShowingAthlete = false
    /// Which of the three day-list pages `dayListPages` is currently selected — always recentered
    /// to `.current` immediately after a swipe commits (see the `onChange` below), so there's
    /// always a "previous"/"next" page on either side to swipe to again. This is the standard
    /// finite-window trick for an apparently-infinite `TabView(.page)` carousel.
    @State private var selectedPage: WeekPage = .current

    private static let weekChangeAnimation: Animation = .easeInOut(duration: 0.25)

    private enum WeekPage: Int, Hashable {
        case previous, current, next
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
                    weekContent
                }
            }
            // Covers the empty-state -> week-content swap once `hasNoActivities` flips (e.g. after
            // "Connect Health Data" completes): that happens asynchronously, well after the button's
            // own `Task` returns, so there's no synchronous call site to wrap in `withAnimation` —
            // animating on the value change itself is the only way to catch it.
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

    /// The chart sits outside the swipeable area — it's a rolling 3-week trend, not "this week's"
    /// content, so it shouldn't visibly drag along with the day list — with only the day-by-day
    /// list underneath living in the paging `TabView`.
    private var weekContent: some View {
        VStack(spacing: 0) {
            FitnessChartView(metrics: viewModel.chartMetrics)
                .padding(.vertical, 8)

            // `TabView(.page)` gives us finger-tracking, edge-peeking of the neighboring weeks,
            // and horizontal-only paging (it doesn't fight the day list's own vertical scrolling)
            // for free — all things a hand-rolled DragGesture had to approximate and got wrong.
            // The three pages are `viewModel.weekDates(offsetWeeks:)` for -1/0/+1: real data, not
            // placeholders, since `chartRange` already keeps the adjacent weeks loaded.
            TabView(selection: $selectedPage) {
                dayList(for: viewModel.weekDates(offsetWeeks: -1))
                    .tag(WeekPage.previous)
                dayList(for: viewModel.weekDates(offsetWeeks: 0))
                    .tag(WeekPage.current)
                dayList(for: viewModel.weekDates(offsetWeeks: 1))
                    .tag(WeekPage.next)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .onChange(of: selectedPage) { _, newPage in
                handlePageChange(to: newPage)
            }
        }
    }

    private func dayList(for dates: [Date]) -> some View {
        List {
            ForEach(dates, id: \.self) { day in
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
    }

    /// Reacts once the page carousel settles on `newPage` (i.e. the swipe already visually
    /// completed) by advancing `viewModel`, then immediately snapping `selectedPage` back to
    /// `.current` — invisibly, since `.current`'s content (recomputed from the now-updated
    /// `displayedWeekStart`) is identical to what `newPage` was already showing.
    private func handlePageChange(to newPage: WeekPage) {
        guard newPage != .current else { return }
        withAnimation(Self.weekChangeAnimation) {
            if newPage == .next {
                viewModel.goToNextWeek()
            } else {
                viewModel.goToPreviousWeek()
            }
        }
        selectedPage = .current
    }

    /// Jumps to the week containing today. No drag and no natural left/right direction (today
    /// could be either side of the displayed week) to page toward, so this just updates
    /// `displayedWeekStart` directly — the currently selected `TabView` page's `List` picks up
    /// the new dates and animates its own row-level changes, without paging anywhere.
    private func goToToday() {
        withAnimation(Self.weekChangeAnimation) {
            viewModel.goToToday()
        }
    }
}
