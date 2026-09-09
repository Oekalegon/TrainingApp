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
    let timeInZoneByDay: [DayTimeInZone]
    /// Owned by `WeekView`, not this view's own `@State`: the current carousel page is torn down
    /// and rebuilt with a fresh identity on every week change (`.id(dates.first)`, needed to reset
    /// the day list's own scroll position) and can also be recycled by the enclosing `LazyVStack`
    /// during scrolling — either would silently reset a plain `@State` back to page 0. Living on
    /// `WeekView` instead means the selected page survives both.
    @Binding var selectedIndex: Int
    /// Tracks the finger during a drag, on top of `selectedIndex`'s base position — 0 while idle,
    /// same role as `WeekView.dragOffset`/`SportStatsPagerView.dragOffset`. Fine to keep as local
    /// `@State`, unlike `selectedIndex`: it's meaningless outside an in-progress gesture, so losing
    /// it to a page rebuild mid-navigation (there's never a gesture in flight when that happens)
    /// isn't observable.
    @State private var dragOffset: CGFloat = 0

    private static let pageCount = 3
    private static let commitThreshold: CGFloat = 0.3
    private static let pageChangeAnimation: Animation = .easeInOut(duration: 0.25)
    /// Tall enough for the tallest page's chart (140pt) plus its legend row and spacing —
    /// `weekPageContent`'s `LazyVStack` needs a fixed height here since the three pages, laid out
    /// side by side in an `HStack`, don't otherwise report one shared height upward the way a
    /// single view would.
    private static let panelHeight: CGFloat = 190

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
                    TimeInZoneChartView(days: timeInZoneByDay)
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
            case .decrement:
                guard selectedIndex > 0 else { return }
                withAnimation(Self.pageChangeAnimation) { selectedIndex -= 1 }
            @unknown default:
                break
            }
        }
    }
}
