import SwiftUI
import TrainingCore

/// The week view's graph panel (MVP1-55, design doc §2.1): pages between "Daily load", "Form"
/// (CTL/ATL/TSB), and "Time in zone" for the displayed week.
///
/// A hand-rolled `DragGesture` + offset carousel, not `TabView(.page)` — same reasoning as
/// `SportStatsPagerView`'s own carousel: `TabView`'s `UIPageViewController`-backed gesture
/// recognizer would compete with `WeekView`'s own week-swipe gesture for a horizontal drag
/// starting on this panel, and `WeekView` already has to explicitly exempt drags that start here
/// from changing the displayed week (see `WeekView.graphPanelFrame`) — a second, independent
/// paging gesture underneath `TabView`'s own would only compound that.
struct GraphPanelPagerView: View {
    let metrics: [FitnessMetrics]
    let displayedWeekRange: ClosedRange<Date>
    let heartRateHistogram: HeartRateHistogram
    /// Called whenever the page changes, so `WeekView` can remember it across a week change or a
    /// scroll-triggered recycle (see `selectedIndex`'s own doc comment for why this is a one-way
    /// callback rather than a `@Binding`).
    let onSelectedIndexChange: (Int) -> Void

    /// Local `@State`, seeded from `initialSelectedIndex` at init — not a `@Binding` to a value
    /// `WeekView` owns, even though the selection does need to survive this view being torn down
    /// and rebuilt (a week change gives the current carousel page a fresh `.id(dates.first)`
    /// identity, needed to reset the day list's own scroll position; the enclosing `LazyVStack` can
    /// also recycle this view during scrolling). A `@Binding` sourced from `WeekView`'s own `@State`
    /// was tried first: since `WeekView.body` re-evaluates on every drag-gesture callback (other
    /// `@State` there changes too, e.g. `graphPanelFrame`), each recomputes a *new* `Binding` value
    /// for this property, and passing a newly-constructed `Binding` on every render made SwiftUI
    /// tear down and rebuild this view's own `DragGesture` recognizer just as often — the gesture
    /// recognized exactly one swipe, then stopped responding to any further touches, having been
    /// silently replaced by a fresh, un-armed recognizer after that first swipe's own state update.
    /// A local `@State`, written back out through `onSelectedIndexChange` instead, keeps the
    /// recognizer's identity — and so its ability to keep recognizing new gestures — stable.
    @State private var selectedIndex: Int
    /// Tracks the finger during a drag, on top of `selectedIndex`'s base position — 0 while idle,
    /// same role as `WeekView.dragOffset`/`SportStatsPagerView.dragOffset`.
    @State private var dragOffset: CGFloat = 0

    /// Shared with `GraphPanelStaticPreview`'s own page dots, so the two stay in visual lockstep.
    static let pageCount = 3
    private static let commitThreshold: CGFloat = 0.3
    private static let pageChangeAnimation: Animation = .easeInOut(duration: 0.25)
    /// Tall enough for the tallest page's chart (140pt) plus its legend row and spacing —
    /// `weekPageContent`'s `LazyVStack` needs a fixed height here since the three pages, laid out
    /// side by side in an `HStack`, don't otherwise report one shared height upward the way a
    /// single view would. Shared with `GraphPanelStaticPreview` so a mid-drag page transition
    /// between the two doesn't visibly change height.
    static let panelHeight: CGFloat = 190

    init(
        metrics: [FitnessMetrics],
        displayedWeekRange: ClosedRange<Date>,
        heartRateHistogram: HeartRateHistogram,
        initialSelectedIndex: Int,
        onSelectedIndexChange: @escaping (Int) -> Void
    ) {
        self.metrics = metrics
        self.displayedWeekRange = displayedWeekRange
        self.heartRateHistogram = heartRateHistogram
        self.onSelectedIndexChange = onSelectedIndexChange
        _selectedIndex = State(initialValue: initialSelectedIndex)
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let pageWidth = geometry.size.width
                HStack(spacing: 0) {
                    DailyLoadChartView(metrics: metrics, displayedWeekRange: displayedWeekRange)
                        .frame(width: pageWidth)
                        // Every page's content actually exists in the layout simultaneously (just
                        // offset out of the clipped, visible area) -- without this, VoiceOver's
                        // element list would include every page's chart, not just the visible one.
                        .accessibilityHidden(selectedIndex != 0)
                    FitnessChartView(metrics: metrics, displayedWeekRange: displayedWeekRange)
                        .frame(width: pageWidth)
                        .accessibilityHidden(selectedIndex != 1)
                    TimeInZoneChartView(histogram: heartRateHistogram)
                        .frame(width: pageWidth)
                        .accessibilityHidden(selectedIndex != 2)
                }
                // Without this, the HStack's own content-hugging height leaves GeometryReader
                // positioning it at the top of this panel's full height rather than centering it —
                // GeometryReader doesn't center its content by default.
                .frame(maxHeight: .infinity, alignment: .center)
                .offset(x: -CGFloat(selectedIndex) * pageWidth + dragOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            let threshold = pageWidth * Self.commitThreshold
                            withAnimation(Self.pageChangeAnimation) {
                                if value.translation.width < -threshold, selectedIndex < Self.pageCount - 1 {
                                    selectedIndex += 1
                                } else if value.translation.width > threshold, selectedIndex > 0 {
                                    selectedIndex -= 1
                                }
                                dragOffset = 0
                            }
                            onSelectedIndexChange(selectedIndex)
                        }
                )
            }
            .frame(height: Self.panelHeight)
            .clipped()

            HStack(spacing: 4) {
                ForEach(0..<Self.pageCount, id: \.self) { index in
                    Circle()
                        // `unhighlightedPillBackground` (6% opacity) is tuned for a large fill
                        // behind contrasting text elsewhere in the day list — at this dot's tiny
                        // 5pt size that reads as nearly invisible, leaving what looks like a
                        // single dot rather than a page indicator. 25% is still clearly
                        // "unselected" next to the solid `.primary` dot — same choice
                        // `SportStatsPagerView`'s own page dots make.
                        .fill(index == selectedIndex ? Color.primary : Color.primary.opacity(0.25))
                        .frame(width: 5, height: 5)
                }
            }
            .accessibilityHidden(true)
        }
        // The drag gesture above has no VoiceOver/Switch Control equivalent on its own -- this
        // lets an adjustable-control swipe (up/down) move between pages the same way the drag
        // does, so paging isn't sighted-only. Same pattern as `SportStatsPagerView`.
        .accessibilityElement(children: .combine)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                guard selectedIndex < Self.pageCount - 1 else { return }
                withAnimation(Self.pageChangeAnimation) { selectedIndex += 1 }
                onSelectedIndexChange(selectedIndex)
            case .decrement:
                guard selectedIndex > 0 else { return }
                withAnimation(Self.pageChangeAnimation) { selectedIndex -= 1 }
                onSelectedIndexChange(selectedIndex)
            @unknown default:
                break
            }
        }
    }
}

/// A non-interactive stand-in for `GraphPanelPagerView`, used for the two off-screen (previous/
/// next week) carousel pages in `WeekView.weekPageContent` — see that call site's own doc comment
/// for why. Those pages are never touched (always `.disabled`), so unlike `GraphPanelPagerView`
/// they carry no local `@State` and no drag gesture at all: they just render whichever chart
/// `selectedIndex` (owned by `WeekView`, passed in fresh on every render) currently names, so they
/// stay in sync with the interactive page instead of freezing on whatever page happened to be
/// selected the first time each one ever mounted. Deliberately a *separate* type from
/// `GraphPanelPagerView` rather than a mode flag on it: giving `GraphPanelPagerView` itself an
/// externally-driven display path (an `isCurrentPage`-style parameter feeding a computed "which
/// page to show" property) was tried first and — even though the interactive instance's own code
/// path was left behaviorally identical — was enough to make its drag gesture stop responding
/// after one swipe, for reasons that didn't reduce to anything as simple as `.id()` churn or a
/// fresh `@Binding` (the two previously-known causes; see `GraphPanelPagerView.selectedIndex`'s
/// own doc comment for the latter). A wholly separate, `@State`-free view for the two pages that
/// were never interactive in the first place sidesteps the question entirely.
struct GraphPanelStaticPreview: View {
    let metrics: [FitnessMetrics]
    let displayedWeekRange: ClosedRange<Date>
    let heartRateHistogram: HeartRateHistogram
    let selectedIndex: Int

    var body: some View {
        VStack(spacing: 8) {
            Group {
                switch selectedIndex {
                case 0:
                    DailyLoadChartView(metrics: metrics, displayedWeekRange: displayedWeekRange)
                case 1:
                    FitnessChartView(metrics: metrics, displayedWeekRange: displayedWeekRange)
                default:
                    TimeInZoneChartView(histogram: heartRateHistogram)
                }
            }
            .frame(height: GraphPanelPagerView.panelHeight)

            HStack(spacing: 4) {
                ForEach(0..<GraphPanelPagerView.pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == selectedIndex ? Color.primary : Color.primary.opacity(0.25))
                        .frame(width: 5, height: 5)
                }
            }
        }
        // Never the one VoiceOver should land on: it's a same-frame preview of a page the user
        // hasn't swiped to yet, not real, independent content — the interactive `GraphPanelPagerView`
        // instance is the only one that should ever surface here.
        .accessibilityHidden(true)
    }
}
