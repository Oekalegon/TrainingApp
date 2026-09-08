import SwiftUI
import TrainingCore

/// The app's single top-level screen (design doc §2.1): a 3-week CTL/ATL/TSB chart centered on
/// the displayed week, that week's activities/plans below it, swipe-to-navigate between weeks,
/// a "Today" toolbar button, and pull-to-refresh import.
public struct WeekView: View {
    @State private var viewModel: WeekViewModel
    @State private var isShowingAthlete = false
    /// The activity currently shown in the detail sheet, or `nil` when none is presented.
    /// `Activity` is `Identifiable`, so `.sheet(item:)` handles show/dismiss from this alone.
    @State private var selectedActivity: Activity?
    /// Horizontal offset applied to the previous/current/next page `HStack`, on top of its base
    /// "current page centered" position — 0 while idle, tracking the finger during a drag, then
    /// animated to a full page width (commit) or back to 0 (cancel) once the drag ends. Nothing
    /// about `displayedWeekStart` changes until then: the model only ever advances in
    /// `completeSwipe(goingForward:)`, once the user has actually lifted their finger.
    @State private var dragOffset: CGFloat = 0
    /// Whether the drag in progress has been determined to be a horizontal swipe — decided once,
    /// from the first `onChanged` sample, and used both to gate `dragOffset` updates and to
    /// disable the day lists' own vertical scrolling for the rest of that gesture (see
    /// `.scrollDisabled(isDraggingHorizontally)` in `dayList(for:)` below), so a horizontal swipe
    /// can't also scroll the list underneath it.
    @State private var isDraggingHorizontally = false
    @State private var hasDeterminedDragDirection = false
    /// `true` from the moment a swipe clears `commitThreshold` until `completeSwipe(goingForward:)`'s
    /// animation and model update both finish. `handleDragChanged`/`handleDragEnded` ignore touches
    /// while this is `true`, so a fast re-swipe can't land mid-animation: overwriting `dragOffset`
    /// directly (as a new drag would) while the previous swipe's `withAnimation` is still running
    /// would visibly stomp it, and the previous swipe's `completion` closure would still fire later
    /// and advance `viewModel` a second, unintended time.
    @State private var isCompletingSwipe = false

    private static let weekChangeAnimation: Animation = .easeInOut(duration: 0.25)
    /// Fraction of the page width a drag needs to clear, at release, to commit to the next/
    /// previous week rather than springing back.
    private static let commitThreshold: CGFloat = 0.3

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
            .sheet(item: $selectedActivity) { activity in
                // Its own NavigationStack: a sheet doesn't inherit the presenting view's
                // navigation bar, and ActivityDetailView's .navigationTitle needs one to render
                // into. The "Close" button is the sheet's dismiss control -- there's no back
                // button to fall back on the way there was when this pushed onto WeekView's stack.
                NavigationStack {
                    ActivityDetailView(viewModel: viewModel.activityDetailViewModel(for: activity))
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") {
                                    selectedActivity = nil
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $isShowingAthlete) {
                AthleteView(viewModel: viewModel.athleteViewModel)
            }
        }
    }

    /// The chart sits outside the swipeable area — it's a rolling 3-week trend, not "this week's"
    /// content, so it shouldn't visibly drag along with the day list — with only the day-by-day
    /// list underneath following the gesture.
    ///
    /// The day list itself is a manual three-page carousel (previous/current/next week, each a
    /// real `dayList`, not a placeholder) rather than `TabView(.page)`: `TabView`'s selection
    /// binding updates — and so, if reacted to directly, `viewModel.displayedWeekStart` would
    /// have updated — as soon as the drag crosses the halfway point, well before the finger lifts.
    /// That let the model (and the chart above) change mid-gesture, which is exactly the
    /// unnatural, too-early flip this was built to avoid. Driving the pages from `dragOffset`
    /// directly keeps the model change (`completeSwipe(goingForward:)`) tied to gesture *end*,
    /// with the remaining distance animating to completion afterward, same as any standard
    /// direct-manipulation paging control.
    private var weekContent: some View {
        VStack(spacing: 0) {
            FitnessChartView(metrics: viewModel.chartMetrics)
                .padding(.vertical, 8)

            GeometryReader { geometry in
                let pageWidth = geometry.size.width
                HStack(spacing: 0) {
                    dayList(for: viewModel.weekDates(offsetWeeks: -1))
                        .frame(width: pageWidth)
                    dayList(for: viewModel.weekDates(offsetWeeks: 0))
                        .frame(width: pageWidth)
                    dayList(for: viewModel.weekDates(offsetWeeks: 1))
                        .frame(width: pageWidth)
                }
                // Base position centers the "current" (middle) page; dragOffset then tracks the
                // finger on top of that.
                .offset(x: -pageWidth + dragOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in handleDragChanged(value) }
                        .onEnded { value in handleDragEnded(value, pageWidth: pageWidth) }
                )
            }
        }
    }

    /// A plain `ScrollView`/`LazyVStack`, not `List`: once MVP1-20 dropped the per-day section
    /// headers, `List` wasn't buying anything here beyond default row styling — and both
    /// `.refreshable` and `.scrollDisabled` (used below) work identically on a `ScrollView`.
    private func dayList(for dates: [Date]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(dates, id: \.self) { day in
                    DayActivitiesSection(
                        activities: viewModel.activities(on: day),
                        plans: viewModel.plans(on: day),
                        workoutName: { viewModel.workout(for: $0)?.name },
                        timeZone: viewModel.athleteTimeZone,
                        onSelectActivity: { selectedActivity = $0 }
                    )
                }
            }
            .padding(.horizontal)
        }
        // Without this, each of the three carousel slots keeps the same underlying scroll view
        // identity (and thus scroll position) across weeks, since only its row data changes --
        // scrolling down in one week would leave the next week's content scrolled to the same
        // offset instead of starting at the top. Keying on the week's first date forces a fresh
        // view (and so a reset scroll position) exactly when the week actually changes, not on
        // every unrelated re-render.
        .id(dates.first)
        .refreshable {
            await viewModel.refresh()
        }
        // Locked for the duration of a horizontal swipe (see `isDraggingHorizontally`), so a
        // committed horizontal drag can't also scroll whichever page it's currently over.
        .scrollDisabled(isDraggingHorizontally)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        guard !isCompletingSwipe else { return }
        if !hasDeterminedDragDirection {
            hasDeterminedDragDirection = true
            isDraggingHorizontally = abs(value.translation.width) > abs(value.translation.height)
        }
        guard isDraggingHorizontally else { return }
        dragOffset = value.translation.width
    }

    private func handleDragEnded(_ value: DragGesture.Value, pageWidth: CGFloat) {
        defer {
            hasDeterminedDragDirection = false
            isDraggingHorizontally = false
        }
        guard !isCompletingSwipe, isDraggingHorizontally else { return }

        if value.translation.width < -pageWidth * Self.commitThreshold {
            completeSwipe(goingForward: true, pageWidth: pageWidth)
        } else if value.translation.width > pageWidth * Self.commitThreshold {
            completeSwipe(goingForward: false, pageWidth: pageWidth)
        } else {
            // Didn't clear the threshold -- spring back to the current week rather than committing.
            withAnimation(Self.weekChangeAnimation) {
                dragOffset = 0
            }
        }
    }

    /// Finishes a swipe that cleared `commitThreshold`: animates `dragOffset` the rest of the way
    /// to fully reveal the next/previous page, then — once that's done — advances `viewModel` and
    /// resets `dragOffset` to 0 in the same (non-animated) beat. That reset is invisible: the
    /// three pages immediately recompute from the new `displayedWeekStart`, and the page that was
    /// just fully shown (e.g. "next") is now, by definition, the same content the "current" slot
    /// recomputes to — so nothing visibly moves a second time.
    private func completeSwipe(goingForward: Bool, pageWidth: CGFloat) {
        isCompletingSwipe = true
        withAnimation(Self.weekChangeAnimation) {
            dragOffset = goingForward ? -pageWidth : pageWidth
        } completion: {
            dragOffset = 0
            if goingForward {
                viewModel.goToNextWeek()
            } else {
                viewModel.goToPreviousWeek()
            }
            isCompletingSwipe = false
        }
    }

    /// Jumps to the week containing today. No drag and no natural left/right direction (today
    /// could be either side of the displayed week) to page toward, so this just updates
    /// `displayedWeekStart` directly — each page's content picks up the new dates and animates its
    /// own row-level changes, without paging anywhere.
    private func goToToday() {
        withAnimation(Self.weekChangeAnimation) {
            viewModel.goToToday()
        }
    }
}
