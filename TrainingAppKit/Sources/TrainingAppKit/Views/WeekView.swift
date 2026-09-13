import SwiftUI
import TrainingCore

/// Background behind the fitness chart (MVP1-56) — plain white (an elevated dark grey in dark
/// mode), distinct from `weekViewBackground` behind the day rows, so title and chart read as one
/// opaque surface while the pinned stats bar (translucent) is the only part of the screen that lets
/// scrolled content show through.
#if os(iOS)
private let chartSectionBackground = Color(.systemBackground)
#else
// This view only ever ships on iOS; the fallback exists purely so TrainingAppKit (built for both
// iOS and macOS, per Package.swift) still compiles on macOS, e.g. for host-side tooling/tests.
private let chartSectionBackground = Color.white
#endif

/// The named coordinate space `weekContent`'s week-swipe `DragGesture` and `weekPageHeader`'s
/// frame measurement (`statsBarFrame`) both use, so a swipe's start point can be compared against
/// the stats bar's on-screen frame in the same terms. A file-scope constant, not a `WeekView`
/// static member: `WeekView`'s own static members are inferred `@MainActor`-isolated (since `View`
/// requires that for its instance side), which a plain `Sendable` `String` doesn't need to be.
private let weekSwipeCoordinateSpace = "WeekView.weekSwipe"

/// The week tab's screen (design doc §2.1): a 3-week CTL/ATL/TSB chart centered on the displayed
/// week, that week's activities/plans below it, swipe-to-navigate between weeks, "Today" and
/// "Select Date" toolbar buttons, and pull-to-refresh import.
public struct WeekView: View {
    let viewModel: WeekViewModel
    #if os(iOS)
    @Environment(\.colorScheme) private var colorScheme
    #endif
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
    /// Decided once per gesture, alongside `isDraggingHorizontally` — `true` when the drag started
    /// inside `statsBarFrame` or `graphPanelFrame`, so this gesture is left entirely to
    /// `SportStatsPagerView`'s/`GraphPanelPagerView`'s own horizontal paging instead of also being
    /// read as a week-swipe. Before those pagers moved inside `weekContent`'s own swipeable area
    /// (MVP1-56, MVP1-55), neither overlapped it, so this wasn't needed — now that they do, without
    /// this, a swipe across either one changes the displayed week instead of (or as well as) paging
    /// it.
    @State private var isSwipeExemptFromWeekChange = false
    /// The pinned stats bar's own on-screen frame, in `weekSwipeCoordinateSpace` — measured only
    /// from the current page's header (see `weekPageHeader`'s own `.onGeometryChange`), so it always
    /// reflects the interactive page rather than being clobbered by an offscreen neighbor's.
    @State private var statsBarFrame: CGRect = .zero
    /// The graph panel's own on-screen frame, in `weekSwipeCoordinateSpace` — same role as
    /// `statsBarFrame`, for `GraphPanelPagerView` (MVP1-55).
    @State private var graphPanelFrame: CGRect = .zero
    /// `true` from the moment a swipe clears `commitThreshold` until `completeSwipe(goingForward:)`'s
    /// animation and model update both finish. `handleDragChanged`/`handleDragEnded` ignore touches
    /// while this is `true`, so a fast re-swipe can't land mid-animation: overwriting `dragOffset`
    /// directly (as a new drag would) while the previous swipe's `withAnimation` is still running
    /// would visibly stomp it, and the previous swipe's `completion` closure would still fire later
    /// and advance `viewModel` a second, unintended time.
    @State private var isCompletingSwipe = false
    /// The pinned stats-bar header's own measured height (MVP1-56) — used to size the day rows'
    /// `minHeight` so the timeline connector still reaches the bottom of a short week. See
    /// `weekPageHeader`'s `.onGeometryChange` for where this is measured.
    @State private var statsBarHeight: CGFloat = 0
    /// The graph panel's currently selected page — kept here too (in addition to
    /// `GraphPanelPagerView`'s own local `@State`) purely as a safety net: `GraphPanelPagerView`
    /// itself no longer gets torn down and rebuilt on a week change (see `weekPage`'s own doc
    /// comment on why `.id(dates.first)` was dropped), so its local `@State` already survives that
    /// on its own, but this still guards against the (currently untriggered, but not impossible)
    /// case of the enclosing `LazyVStack` recycling the panel during scrolling. See
    /// `GraphPanelPagerView.selectedIndex`'s own doc comment for why this is a one-way callback
    /// (`GraphPanelPagerView.onSelectedIndexChange`), not a `@Binding`.
    @State private var graphPanelSelectedIndex = 0

    private static let weekChangeAnimation: Animation = .easeInOut(duration: 0.25)
    /// The scroll anchor `weekPage`'s `ScrollViewReader` scrolls back to on a week change — see
    /// that call site's own doc comment for why an explicit `scrollTo` replaced `.id(dates.first)`
    /// forcing a fresh `ScrollView`.
    private static let weekPageTopID = "WeekView.weekPageTop"
    /// Fraction of the page width a drag needs to clear, at release, to commit to the next/
    /// previous week rather than springing back.
    private static let commitThreshold: CGFloat = 0.3

    public init(viewModel: WeekViewModel) {
        self.viewModel = viewModel
    }

    #if os(iOS)
    /// A concrete resolved color, not `chartSectionBackground` itself — see the `.toolbarBackground`
    /// call site in `body` for why the toolbar needs a resolved (non-dynamic) color to render flat.
    private var toolbarBackgroundColor: Color {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        return Color(UIColor.systemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
    }
    #endif

    /// `.topBarLeading` doesn't exist on macOS — this view only ever ships on iOS, but
    /// `TrainingAppKit` is built for both iOS and macOS (per `Package.swift`), so `.navigation`
    /// here is unused in practice, just kept for the package to compile on macOS.
    private var leadingToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
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
            // A light (dark in dark mode) grey rather than the plain system background, so
            // DayActivitiesSection's pills/timeline (recessed relative to this) and its activity
            // cards (elevated relative to this) both have something to visually contrast against.
            .background(weekViewBackground.ignoresSafeArea())
            // Covers the empty-state -> week-content swap once `hasNoActivities` flips (e.g. after
            // "Connect Health Data" completes): that happens asynchronously, well after the button's
            // own `Task` returns, so there's no synchronous call site to wrap in `withAnimation` —
            // animating on the value change itself is the only way to catch it.
            .animation(Self.weekChangeAnimation, value: viewModel.hasNoActivities)
            // The native title/subtitle (MVP1-56), not a custom header view: this gets the toolbar
            // buttons' Liquid Glass styling for free, rather than reimplementing it by hand.
            // Left at the default (large) display mode, not forced `.inline`: `weekContent`'s single
            // `ScrollView` per page (MVP1-56) lets the system's own large-title collapse engage
            // natively — title and chart scroll away together as the day list scrolls, exactly like
            // Mail's message list, rather than an abrupt manual swap between two fixed styles.
            .navigationTitle("Week \(viewModel.displayedWeekOfYear)")
            #if os(iOS)
            .navigationSubtitle(viewModel.displayedWeekDateRangeDescription)
            // A concrete resolved color, not `chartSectionBackground` itself: passed a dynamic/
            // system `Color` (e.g. `Color(.systemBackground)`), the toolbar still renders its own
            // translucent "glass" chrome layered on top. Deliberately without a paired
            // `.toolbarBackground(.visible, for:)`: forcing that broke the large title from ever
            // reappearing once scrolled back to the top — the system's own `.automatic` visibility
            // (background shown once scrolled, hidden at the top) works correctly on its own and
            // still uses this color whenever it does show it.
            .toolbarBackground(toolbarBackgroundColor, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: leadingToolbarPlacement) {
                    Button("Previous Week", systemImage: "chevron.left") {
                        navigate(to: viewModel.weekDates(offsetWeeks: -1).first ?? viewModel.displayedWeekStart)
                    }
                }
                ToolbarItem(placement: leadingToolbarPlacement) {
                    Button("Next Week", systemImage: "chevron.right") {
                        navigate(to: viewModel.weekDates(offsetWeeks: 1).first ?? viewModel.displayedWeekStart)
                    }
                }
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
                            navigate(to: pickedDate)
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

    /// The day list itself is a manual three-page carousel (previous/current/next week, each a
    /// real `weekPage`, not a placeholder) rather than `TabView(.page)`: `TabView`'s selection
    /// binding updates — and so, if reacted to directly, `viewModel.displayedWeekStart` would
    /// have updated — as soon as the drag crosses the halfway point, well before the finger lifts.
    /// That let the model change mid-gesture, which is exactly the unnatural, too-early flip this
    /// was built to avoid. Driving the pages from `dragOffset` directly keeps the model change
    /// (`completeSwipe(goingForward:)`) tied to gesture *end*, with the remaining distance
    /// animating to completion afterward, same as any standard direct-manipulation paging control.
    ///
    /// Only the middle (current) page is ever actually interactive — see `weekPage`'s own doc
    /// comment for why the other two are permanently disabled rather than just during a drag.
    private var weekContent: some View {
        GeometryReader { geometry in
            let pageWidth = geometry.size.width
            let pageHeight = geometry.size.height
            HStack(spacing: 0) {
                weekPage(for: viewModel.weekDates(offsetWeeks: -1), pageHeight: pageHeight, isCurrentPage: false)
                    .frame(width: pageWidth)
                weekPage(for: viewModel.weekDates(offsetWeeks: 0), pageHeight: pageHeight, isCurrentPage: true)
                    .frame(width: pageWidth)
                weekPage(for: viewModel.weekDates(offsetWeeks: 1), pageHeight: pageHeight, isCurrentPage: false)
                    .frame(width: pageWidth)
            }
            // Base position centers the "current" (middle) page; dragOffset then tracks the
            // finger on top of that.
            .offset(x: -pageWidth + dragOffset)
            // Named so `weekPageHeader` can report `statsBarFrame` in the same coordinate space
            // this gesture's own `value.startLocation` uses (its `.local`, by default) — that's
            // what lets `handleDragChanged` tell a swipe starting on the stats bar apart from one
            // starting anywhere else on the page.
            .coordinateSpace(.named(weekSwipeCoordinateSpace))
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in handleDragChanged(value) }
                    .onEnded { value in handleDragEnded(value, pageWidth: pageWidth) }
            )
        }
    }

    /// One week's full scrollable content (MVP1-56): the fitness chart scrolls away with the nav
    /// bar's large title (both are content above the pinned section, so they collapse together as
    /// the same `ScrollView` scrolls — exactly like Mail's message list), then the main-sport stats
    /// bar pins to the top of the page, translucent so the day rows are still dimly visible
    /// scrolling underneath it, the same way a native pinned section header works — see
    /// `weekPageHeader`'s own doc comment for the exact material.
    ///
    /// A plain `ScrollView`/`LazyVStack`, not `List`, for the day rows: once MVP1-20 dropped the
    /// per-day section headers, `List` wasn't buying anything here beyond default row styling — and
    /// both `.refreshable` and `.scrollDisabled` (used below) work identically on a `ScrollView`.
    ///
    /// - Parameters:
    ///   - pageHeight: The week view's own visible height (from `weekContent`'s `GeometryReader`)
    ///     — the day rows are given at least `pageHeight` minus the stats bar's own measured height
    ///     as their `minHeight`, with a trailing filler segment absorbing whatever's left over, so
    ///     the timeline extends all the way to the bottom of the week view even on a short week
    ///     rather than stopping right after the last day's own content.
    ///   - isCurrentPage: `true` only for the middle (currently displayed) carousel page. The other
    ///     two exist purely so their content is ready to slide into view mid-drag — a real user
    ///     never scrolls them directly, so they're rendered as plain, non-scrolling content rather
    ///     than a second and third `ScrollView`. That's not just an optimization: the system binds
    ///     its large-title collapse tracking to the first `ScrollView` it finds in the hierarchy,
    ///     which — with three side-by-side candidates, only one of which the user can actually
    ///     scroll — is never guaranteed to be the visible one. Keeping exactly one real `ScrollView`
    ///     in the tree at a time is what makes the title reliably track *this* page's scrolling.
    private func weekPage(for dates: [Date], pageHeight: CGFloat, isCurrentPage: Bool) -> some View {
        Group {
            if isCurrentPage {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        weekPageContent(for: dates, pageHeight: pageHeight, isCurrentPage: true)
                            .id(Self.weekPageTopID)
                    }
                    .refreshable {
                        await viewModel.refresh()
                    }
                    // Locked for the duration of a horizontal swipe (see `isDraggingHorizontally`),
                    // so a committed horizontal drag can't also scroll the page underneath it.
                    .scrollDisabled(isDraggingHorizontally)
                    // Explicit scroll-to-top on a week change, not `.id(dates.first)` forcing a
                    // fresh `ScrollView` (this page's own previous approach, and still `weekPage`'s
                    // pattern before MVP1-55): tearing the `ScrollView` down and rebuilding it while
                    // `completeSwipe`'s own `withAnimation` (on the *ancestor* `weekContent` HStack)
                    // was still resolving left `GraphPanelPagerView`'s freshly-remounted drag
                    // gesture permanently unable to recognize any further touches — a `ScrollView`
                    // that's never torn down doesn't have that failure mode, and this reaches the
                    // same "start the new week scrolled to the top" result without it.
                    .onChange(of: dates.first) { _, _ in
                        // Deferred a tick, not called directly: `weekPageContent`'s own layout for
                        // the new `dates` hasn't necessarily finished by the time this fires in the
                        // same update as the data change, and `scrollTo` acting on the still-stale
                        // geometry silently did nothing.
                        DispatchQueue.main.async {
                            scrollProxy.scrollTo(Self.weekPageTopID, anchor: .top)
                        }
                    }
                }
            } else {
                // No ScrollView: this page is only ever glimpsed mid-drag, so it's pinned to its
                // resting (scrolled-to-top) appearance and clipped to the visible page bounds.
                weekPageContent(for: dates, pageHeight: pageHeight, isCurrentPage: false)
                    .frame(height: pageHeight, alignment: .top)
                    .clipped()
            }
        }
        // Same reasoning as `.scrollDisabled` above, for taps: without this, a horizontal swipe
        // that starts on an `ActivityRow`/`PlannedActivityRow` button still recognizes as a tap on
        // release and opens the activity detail sheet in addition to paging the week.
        // `.allowsHitTesting(false)` doesn't help here -- the button's tap gesture already started
        // tracking the touch at touch-down, before `isDraggingHorizontally` flips, so blocking new
        // hit-tests mid-drag doesn't cancel it. `.disabled` does: SwiftUI re-checks `isEnabled` at
        // the moment the tap actually fires (touch-up), not at touch-down, so flipping it during
        // the drag suppresses the action. The non-current pages are always disabled outright, since
        // they're never meant to be tapped at all. `isSwipeExemptFromWeekChange` carves out the one
        // case that isn't a week-swipe at all (a drag starting on the pinned stats bar) — without
        // it, this would also disable `SportStatsPagerView`'s own paging gesture for the whole drag,
        // defeating the exemption `handleDragChanged` grants it.
        .disabled(!isCurrentPage || (isDraggingHorizontally && !isSwipeExemptFromWeekChange))
    }

    /// The graph panel shown atop one week's page: the interactive `GraphPanelPagerView` for the
    /// current page, a non-interactive `GraphPanelStaticPreview` for the other two — see that
    /// type's own doc comment for why they're two distinct view types (rather than one view with
    /// an `isCurrentPage`-style mode flag) and why the two off-screen pages need their own display
    /// path here at all rather than just reusing `GraphPanelPagerView` with a frozen initial page.
    @ViewBuilder
    private func graphPanel(weekStart: Date, isCurrentPage: Bool) -> some View {
        if isCurrentPage {
            GraphPanelPagerView(
                metrics: viewModel.chartMetrics,
                displayedWeekRange: viewModel.displayedWeekRange,
                heartRateHistogram: viewModel.heartRateHistogram(for: weekStart),
                initialSelectedIndex: graphPanelSelectedIndex,
                onSelectedIndexChange: { graphPanelSelectedIndex = $0 }
            )
        } else {
            GraphPanelStaticPreview(
                metrics: viewModel.chartMetrics,
                displayedWeekRange: viewModel.displayedWeekRange,
                heartRateHistogram: viewModel.heartRateHistogram(for: weekStart),
                selectedIndex: graphPanelSelectedIndex
            )
        }
    }

    /// The shared content for one week's page — see `weekPage`'s own doc comment for why only the
    /// current page wraps this in a real `ScrollView`. `isCurrentPage` is threaded down to
    /// `weekPageHeader` and the graph panel purely so they know whether to report their frames for
    /// gesture disambiguation (see `statsBarFrame`'s own doc comment) — a non-current page's frames
    /// are meaningless for that since the page isn't the one on screen being swiped.
    @ViewBuilder
    private func weekPageContent(for dates: [Date], pageHeight: CGFloat, isCurrentPage: Bool) -> some View {
        let weekStart = dates.first ?? viewModel.displayedWeekStart
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            graphPanel(weekStart: weekStart, isCurrentPage: isCurrentPage)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(chartSectionBackground)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(weekSwipeCoordinateSpace))
                } action: { _, newFrame in
                    guard isCurrentPage else { return }
                    graphPanelFrame = newFrame
                }
            Section {
                VStack(alignment: .leading, spacing: 0) {
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
                    // Continues the timeline past the last day's own connector (which stops at
                    // that day's own bottom padding) down through whatever space `minHeight`
                    // below adds — same line color/width/x-offset as `DayActivitiesSection`'s
                    // own connector (shared via `WeekdayPillView`'s constants), so it reads as
                    // one uninterrupted line rather than two segments that happen to line up.
                    Rectangle()
                        .fill(unhighlightedPillBackground)
                        .frame(width: WeekdayPillView.connectorLineWidth)
                        .padding(.leading, WeekdayPillView.connectorLineLeadingPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(minHeight: max(0, pageHeight - statsBarHeight), alignment: .top)
                .padding(.horizontal)
                // Without this, the first weekday pill sits flush against the divider at the
                // bottom of the pinned stats bar (MVP1-52) — everything below the first row
                // already has this same breathing room via each `DayActivitiesSection`'s own
                // `.padding(.bottom, 20)`.
                .padding(.top, 12)
            } header: {
                weekPageHeader(weekStart: weekStart, isCurrentPage: isCurrentPage)
            }
        }
    }

    /// The pinned stats bar (MVP1-56) — see `weekPage`'s own doc comment for how it fits into the
    /// scroll hierarchy. Lightly translucent (`.thinMaterial`) so the day rows read as scrolling
    /// underneath it once pinned, not behind an opaque panel — unlike `chartSectionBackground` above
    /// it, which is deliberately opaque. `.ultraThinMaterial` let too much of the grey day-list
    /// background bleed/tint through, reading as noticeably darker than the white chart above it.
    ///
    /// - Parameter isCurrentPage: Gates whether this instance reports its frame into `statsBarFrame`
    ///   — see that property's own doc comment. All three carousel pages mount a `weekPageHeader`,
    ///   but only the current one is actually on screen/interactive, so only it should be allowed to
    ///   write that shared state (the other two's frames are for offscreen content).
    private func weekPageHeader(weekStart: Date, isCurrentPage: Bool) -> some View {
        VStack(spacing: 0) {
            Divider()
            SportStatsPagerView(pages: viewModel.sportStatsPages(for: weekStart))
                .padding(.vertical, 12)
            Divider()
        }
        .background(.thinMaterial)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { _, newHeight in
            statsBarHeight = newHeight
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(weekSwipeCoordinateSpace))
        } action: { _, newFrame in
            guard isCurrentPage else { return }
            statsBarFrame = newFrame
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        guard !isCompletingSwipe else { return }
        if !hasDeterminedDragDirection {
            hasDeterminedDragDirection = true
            isDraggingHorizontally = abs(value.translation.width) > abs(value.translation.height)
            isSwipeExemptFromWeekChange = statsBarFrame.contains(value.startLocation)
                || graphPanelFrame.contains(value.startLocation)
        }
        guard isDraggingHorizontally, !isSwipeExemptFromWeekChange else { return }
        dragOffset = value.translation.width
    }

    private func handleDragEnded(_ value: DragGesture.Value, pageWidth: CGFloat) {
        defer {
            hasDeterminedDragDirection = false
            isDraggingHorizontally = false
            isSwipeExemptFromWeekChange = false
        }
        guard !isCompletingSwipe, isDraggingHorizontally, !isSwipeExemptFromWeekChange else { return }

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
    /// resets `dragOffset` to 0 in the same beat. That reset is invisible: the three pages
    /// immediately recompute from the new `displayedWeekStart`, and the page that was just fully
    /// shown (e.g. "next") is now, by definition, the same content the "current" slot recomputes
    /// to — so nothing visibly moves a second time.
    ///
    /// Preloads the target week's own 3-week chart range *concurrently* with the slide animation,
    /// not after it (MVP1-32): advancing `displayedWeekStart` first and only then loading (as
    /// `WeekView`'s own `.task(id: viewModel.displayedWeekStart)` does) leaves a window where the
    /// chart's `chartMetrics` filters the *not-yet-updated* `model.metrics` by the *new*
    /// `chartRange` — a genuine gap (e.g. the week furthest from the swipe direction briefly
    /// missing entirely), not just stale data. Starting the preload here, alongside the slide
    /// rather than in its `completion`, means the wait for it (if any) is `max(slide duration,
    /// preload duration)` instead of the sum of the two — awaiting it only after the slide already
    /// finished would extend, not shrink, how long the incoming page keeps showing the old week's
    /// data before flipping.
    private func completeSwipe(goingForward: Bool, pageWidth: CGFloat) {
        isCompletingSwipe = true
        let targetWeekStart = viewModel.weekDates(offsetWeeks: goingForward ? 1 : -1).first
        let preload = Task {
            if let targetWeekStart {
                await viewModel.preload(weekStart: targetWeekStart)
            }
        }
        withAnimation(Self.weekChangeAnimation) {
            dragOffset = goingForward ? -pageWidth : pageWidth
        } completion: {
            Task {
                await preload.value
                dragOffset = 0
                if goingForward {
                    viewModel.goToNextWeek()
                } else {
                    viewModel.goToPreviousWeek()
                }
                isCompletingSwipe = false
            }
        }
    }

    /// Jumps to the week containing today. No drag and no natural left/right direction (today
    /// could be either side of the displayed week) to page toward, so this just updates
    /// `displayedWeekStart` directly — each page's content picks up the new dates and animates its
    /// own row-level changes, without paging anywhere.
    private func goToToday() {
        navigate(to: .now)
    }

    /// Preloads `date`'s own week's chart range, then (animated) navigates `displayedWeekStart`
    /// there — shared by the toolbar's Previous/Next Week and "Today" buttons and "Select Date",
    /// none of which page through the target week the way a swipe does.
    ///
    /// Without the preload, each of these would exhibit the same flash `completeSwipe` guards
    /// against (MVP1-32; see that method's own doc comment, and
    /// `WeekViewModel.preload(weekStart:asOf:)`'s, for why) — a bare, unpreloaded
    /// `displayedWeekStart` assignment briefly leaves `chartMetrics` filtering the *old*
    /// `model.metrics` by the *new* `chartRange`, so the graph flashes the previous week's now-
    /// incomplete shape until `WeekView`'s own `.task(id: viewModel.displayedWeekStart)` catches up.
    /// `WeekViewModel.weekStart(containing:calendar:)` resolves `date` to its own week's start
    /// first, so the preloaded range lines up exactly with what `chartRange` becomes once
    /// `goToWeek(containing:)` actually navigates there — passing `date` itself (e.g. "now",
    /// partway through today) straight to `preload(weekStart:)` would offset the preloaded range
    /// from the final one by however far `date` sits into its own week.
    ///
    /// Deliberately *not* wrapped in `withAnimation`, unlike this method's own previous revision:
    /// none of `FitnessChartView`/`DailyLoadChartView`/`HeartRateHistogramChartView` apply their
    /// own `.animation(_:value:)`, so an explicit `withAnimation` here was the only thing making
    /// Swift Charts interpolate — its marks are `Animatable` and, given one, smoothly slide their
    /// values and `chartXScale` domain from the old 3-week window to the new one. Since the data
    /// itself is already complete by the time this assignment runs (the preload above finished
    /// first), that interpolation had nothing to do with correctness — but visually it looked
    /// exactly like the target week's data "growing in" after the rest, which is the bug this
    /// preload was meant to fix in the first place. A plain, unanimated assignment instead snaps
    /// straight to the final, complete state.
    private func navigate(to date: Date) {
        let weekStart = WeekViewModel.weekStart(containing: date, calendar: viewModel.athleteCalendar)
        Task {
            await viewModel.preload(weekStart: weekStart)
            viewModel.goToWeek(containing: date)
        }
    }
}
