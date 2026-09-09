import SwiftUI
import TrainingCore

/// The week tab's screen (design doc §2.1): a 3-week CTL/ATL/TSB chart centered on the displayed
/// week, that week's activities/plans below it, swipe-to-navigate between weeks, "Today" and
/// "Select Date" toolbar buttons, and pull-to-refresh import.
public struct WeekView: View {
    let viewModel: WeekViewModel
    /// Whether the "Select Date" sheet is presented.
    @State private var isShowingDatePicker = false
    /// The date picked in the "Select Date" sheet — seeded from `displayedWeekStart` each time
    /// the sheet opens, so the picker starts near whatever week is currently on screen.
    @State private var pickedDate = Date()
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

    public init(viewModel: WeekViewModel) {
        self.viewModel = viewModel
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
                    Button("Select Date", systemImage: "calendar.badge.clock") {
                        pickedDate = viewModel.displayedWeekStart
                        isShowingDatePicker = true
                    }
                }
            }
            .task(id: viewModel.displayedWeekStart) {
                await viewModel.load()
            }
            .sheet(item: $selectedActivity) { activity in
                // Its own NavigationStack: a sheet doesn't inherit the presenting view's
                // navigation bar, and ActivityDetailView's .navigationTitle needs one to render
                // into. Dismissal is the standard swipe-down gesture every sheet gets for free --
                // no explicit close button.
                NavigationStack {
                    ActivityDetailView(viewModel: viewModel.activityDetailViewModel(for: activity))
                }
            }
            .sheet(isPresented: $isShowingDatePicker) {
                datePickerSheet
            }
        }
    }

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker("Date", selection: $pickedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding()
                // Without `.timeZone`, the picker resolves "the selected day" using the device's
                // time zone, which `goToWeek(containing:)` then reinterprets in the athlete's — a
                // mismatch (e.g. traveling) could silently land on the wrong week for a date near
                // midnight. Without `.calendar`, the graphical grid's rows would start on the
                // device locale's first weekday rather than `AthleteProfile.weekStartsOn`, which
                // `goToWeek(containing:)` still resolves correctly but would visually disagree
                // with -- e.g. rows starting Sunday while the app's own weeks start Monday.
                .environment(\.timeZone, viewModel.athleteTimeZone)
                .environment(\.calendar, viewModel.athleteCalendar)
                .navigationTitle("Select Date")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            withAnimation(Self.weekChangeAnimation) {
                                viewModel.goToWeek(containing: pickedDate)
                            }
                            isShowingDatePicker = false
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isShowingDatePicker = false
                        }
                    }
                }
        }
        .presentationDetents([.medium])
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
            FitnessChartView(metrics: viewModel.chartMetrics, displayedWeekRange: viewModel.displayedWeekRange)
                .padding(.vertical, 8)

            GeometryReader { geometry in
                let pageWidth = geometry.size.width
                let pageHeight = geometry.size.height
                HStack(spacing: 0) {
                    dayList(for: viewModel.weekDates(offsetWeeks: -1), pageHeight: pageHeight)
                        .frame(width: pageWidth)
                    dayList(for: viewModel.weekDates(offsetWeeks: 0), pageHeight: pageHeight)
                        .frame(width: pageWidth)
                    dayList(for: viewModel.weekDates(offsetWeeks: 1), pageHeight: pageHeight)
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
    ///
    /// - Parameter pageHeight: The week view's own visible height (from `weekContent`'s
    ///   `GeometryReader`) — the `LazyVStack` is given at least this as its `minHeight`, and a
    ///   trailing filler segment after the last day absorbs whatever's left over, so the timeline
    ///   extends all the way to the bottom of the week view even on a short week rather than
    ///   stopping right after the last day's own content.
    private func dayList(for dates: [Date], pageHeight: CGFloat) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(dates.enumerated()), id: \.element) { index, day in
                    DayActivitiesSection(
                        date: day,
                        isToday: viewModel.isToday(day),
                        showsConnector: true,
                        metrics: viewModel.metrics(on: day),
                        activities: viewModel.activities(on: day),
                        plans: viewModel.plans(on: day),
                        workoutName: { viewModel.workout(for: $0)?.name },
                        trainingLoad: { viewModel.trainingLoad(for: $0) },
                        timeZone: viewModel.athleteTimeZone,
                        onSelectActivity: { selectedActivity = $0 }
                    )
                }
                // Continues the timeline past the last day's own connector (which stops at that
                // day's own bottom padding) down through whatever space `minHeight` below adds —
                // same line color/x-offset as `DayActivitiesSection`'s own connector, so it reads
                // as one uninterrupted line rather than two segments that happen to line up.
                Rectangle()
                    .fill(unhighlightedPillBackground)
                    .frame(width: 2)
                    .padding(.leading, WeekdayPillView.columnWidth / 2 - 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: pageHeight, alignment: .top)
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
        // Same reasoning, for taps: without this, a horizontal swipe that starts on an
        // `ActivityRow`/`PlannedActivityRow` button still recognizes as a tap on release and opens
        // the activity detail sheet in addition to paging the week. `.allowsHitTesting(false)`
        // doesn't help here -- the button's tap gesture already started tracking the touch at
        // touch-down, before `isDraggingHorizontally` flips, so blocking new hit-tests mid-drag
        // doesn't cancel it. `.disabled` does: SwiftUI re-checks `isEnabled` at the moment the tap
        // actually fires (touch-up), not at touch-down, so flipping it during the drag suppresses
        // the action.
        .disabled(isDraggingHorizontally)
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
