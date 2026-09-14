import SwiftUI
import TrainingCore

/// Per-sport stats shown directly below the fitness chart (design doc: `AthleteProfile.mainSport`,
/// MVP1-52) — one swipeable page per sport with activity in the displayed week, main sport first.
/// A fixed leading icon (the current page's sport) plus paging dots stay in place while the
/// trailing Distance/Time/Load figures page underneath, each followed by its percentage change
/// versus the previous week. Distance and time are omitted for a non-endurance sport (e.g.
/// `.strength`), same rule `ActivityCard` uses for its own second line; Load is always the whole
/// week's total across every sport (see `SportStatsPage`'s own doc comment), so it reads the same
/// on every page.
///
/// Below that row, a second line reports the *currently paged-to sport's* 80/20 low-intensity
/// split (MVP1-48) — unlike `load`, this genuinely varies per sport (see `SportStatsPage`'s own
/// doc comment for why blending it across sports would defeat the guideline's point), so it
/// follows `selectedIndex` the same way the leading icon does: it updates once a swipe commits to
/// a new page, not continuously during the drag. Omitted entirely when the selected sport has no
/// zone-classified time at all that week (no heart-rate data, no planned workout with an intensity
/// target). This is a separate row rather than a fourth item in the pager's own trailing HStack:
/// that row is already tight (icon, paging dots, and up to three per-page stat items in a fixed
/// 44pt height, sized for the narrowest supported device) — adding another column there risked
/// squeezing or clipping the existing figures.
struct SportStatsPagerView: View {
    let pages: [SportStatsPage]

    /// Index into `pages`, not a `Sport` tag: unlike `WeekView`'s own day-list carousel (always
    /// exactly 3 fixed slots), the *number* of pages here varies week to week, so an index is what
    /// stays meaningful across a `pages` change (see the `onChange` below, which resets it rather
    /// than trying to re-locate a sport that may no longer be present).
    @State private var selectedIndex = 0
    /// Tracks the finger during a drag, on top of `selectedIndex`'s base position — 0 while idle,
    /// same role as `WeekView.dragOffset`.
    @State private var dragOffset: CGFloat = 0

    private static let commitThreshold: CGFloat = 0.3
    private static let pageChangeAnimation: Animation = .easeInOut(duration: 0.25)

    private var selectedSport: Sport {
        pages.indices.contains(selectedIndex) ? pages[selectedIndex].sport : (pages.first?.sport ?? .running)
    }

    /// The selected page's own low-intensity fraction — same `selectedIndex`-with-`pages.first`
    /// fallback as `selectedSport` — or `nil` when that sport has no zone-classified time at all
    /// this week, so the caption row below is omitted rather than showing a meaningless "0%".
    private var polarizedSplit: PolarizedIntensitySplit? {
        let page = pages.indices.contains(selectedIndex) ? pages[selectedIndex] : pages.first
        let split = page?.polarizedSplit
        return (split?.total ?? 0) > 0 ? split : nil
    }

    var body: some View {
        VStack(spacing: 4) {
            statsBar
            if let polarizedSplit {
                lowIntensityCaption(for: polarizedSplit)
            }
        }
    }

    private var statsBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: selectedSport.symbolName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    // No adjacent text names the sport here (icon-only, unlike `ActivityCard`'s
                    // icon+name pairing) — without an explicit label, VoiceOver would announce
                    // only the icon's own SF Symbol name instead of the sport it stands for.
                    .accessibilityLabel(selectedSport.displayName)

                if pages.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { index, _ in
                            Circle()
                                // `unhighlightedPillBackground` (6% opacity) is tuned for a large
                                // fill behind contrasting text elsewhere in the day list — at this
                                // dot's tiny 5pt size that reads as nearly invisible, leaving what
                                // looks like a single dot rather than a page indicator. 25% is
                                // still clearly "unselected" next to the solid `.primary` dot.
                                .fill(index == selectedIndex ? Color.primary : Color.primary.opacity(0.25))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }

            // A hand-rolled `DragGesture` + offset carousel, not `TabView(.page)`: squeezed into
            // this row's ~44pt height, `TabView(.page)`'s UIPageViewController-backed gesture
            // recognizer doesn't respect that tight height for hit-testing — a swipe square inside
            // this row's own visible bounds was silently captured by `WeekView`'s day-list swipe
            // gesture instead of paging here. `WeekView`'s own carousel already avoids `TabView`
            // for unrelated reasons (see its doc comment); the same manual approach sidesteps this
            // interop issue too, and works identically on iOS and macOS.
            GeometryReader { geometry in
                let pageWidth = geometry.size.width
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        StatsPageView(page: page)
                            .frame(width: pageWidth)
                            // Every page's content actually exists in the layout simultaneously
                            // (just offset out of the clipped, visible area) -- without this,
                            // VoiceOver's element list would include every page's Distance/Time/
                            // Load text, not just whichever one is actually on screen.
                            .accessibilityHidden(index != selectedIndex)
                    }
                }
                // Without this, the `HStack`'s own natural (content-hugging) height leaves
                // `GeometryReader` positioning it at the top of this row's full 44pt height rather
                // than centering it — `GeometryReader` doesn't center its content by default, unlike
                // the icon+dots `HStack` alongside it, which does get that from this view's outer
                // `HStack`'s own default `.center` alignment.
                .frame(maxHeight: .infinity, alignment: .center)
                .offset(x: -CGFloat(selectedIndex) * pageWidth + dragOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            // No-op with a single page: nothing to page to, so the content
                            // shouldn't visibly rubber-band on a stray horizontal touch.
                            guard pages.count > 1 else { return }
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            guard pages.count > 1 else { return }
                            let threshold = pageWidth * Self.commitThreshold
                            withAnimation(Self.pageChangeAnimation) {
                                if value.translation.width < -threshold, selectedIndex < pages.count - 1 {
                                    selectedIndex += 1
                                } else if value.translation.width > threshold, selectedIndex > 0 {
                                    selectedIndex -= 1
                                }
                                dragOffset = 0
                            }
                        }
                )
            }
            .clipped()
        }
        .padding(.horizontal)
        .frame(height: 44)
        // Without this, paging to a non-main-sport index and then navigating to a week with fewer
        // pages could leave `selectedIndex` pointing past the end of the new `pages`, or simply on
        // whatever sport happens to now sit at that same index rather than back on the main sport.
        .onChange(of: pages.map(\.sport)) { _, _ in
            selectedIndex = 0
        }
        // The drag gesture above has no VoiceOver/Switch Control equivalent on its own -- this
        // lets an adjustable-control swipe (up/down) move between pages the same way the drag
        // does, so paging isn't sighted-only.
        .accessibilityElement(children: .combine)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                guard selectedIndex < pages.count - 1 else { return }
                withAnimation(Self.pageChangeAnimation) { selectedIndex += 1 }
            case .decrement:
                guard selectedIndex > 0 else { return }
                withAnimation(Self.pageChangeAnimation) { selectedIndex -= 1 }
            @unknown default:
                break
            }
        }
    }

    /// A trailing-aligned caption reporting `split`'s low-intensity fraction, e.g. "82% low
    /// intensity this week" — its own accessibility element, separate from `statsBar`'s combined
    /// one, since it doesn't page and isn't part of that gesture-driven carousel. `.footnote`, not
    /// `.caption2`, to match `StatsPageView`'s own value figures (see its `statItem`'s doc comment
    /// for why they share one fixed size rather than each auto-shrinking to its own content).
    private func lowIntensityCaption(for split: PolarizedIntensitySplit) -> some View {
        let percent = split.lowFraction.formatted(.percent.precision(.fractionLength(0)))
        return HStack {
            Spacer()
            Text("\(percent) low intensity this week")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}

/// One page's Distance/Time/Load figures, each followed by its percentage change — the swipeable
/// content `SportStatsPagerView`'s carousel pages between.
private struct StatsPageView: View {
    let page: SportStatsPage

    private static let distanceFormat = Measurement<UnitLength>.FormatStyle.measurement(width: .abbreviated)
    private static let loadFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
    /// Always shows a sign (matching `DayMetricsPillRow`'s TSB format), so "no change" reads as an
    /// explicit "+0%" rather than a bare, ambiguous "0%".
    private static let percentFormat = FloatingPointFormatStyle<Double>.Percent.percent
        .sign(strategy: .always()).precision(.fractionLength(0))

    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)

            if page.sport.isEndurance {
                statItem(value: distanceString, changeFraction: page.distanceChangeFraction, label: "Distance")
                statItem(value: durationString, changeFraction: page.timeChangeFraction, label: "Time")
            }
            statItem(value: loadString, changeFraction: page.loadChangeFraction, label: "Load")
        }
        .accessibilityElement(children: .combine)
    }

    private var distanceString: String {
        Measurement(value: page.distanceMeters, unit: UnitLength.meters).formatted(Self.distanceFormat)
    }

    private var durationString: String {
        Duration.seconds(page.time).formatted(.time(pattern: .hourMinuteSecond))
    }

    private var loadString: String {
        page.load.formatted(Self.loadFormat)
    }

    private func statItem(value: String, changeFraction: Double, label: String) -> some View {
        let percentText = Text(percentString(changeFraction))
            .font(.caption2)
            .foregroundStyle(.secondary)
        return VStack(alignment: .trailing, spacing: 0) {
            // One `Text` built via interpolation, not two `Text`s in an `HStack`: value and
            // percentage need to scale down *together* when three stat items plus the sport icon
            // don't all fit at full size (e.g. a multi-digit-hour duration like "2:00:00" beside
            // its "+33%") — `.minimumScaleFactor` only has that effect within a single `Text`, and
            // without it the value can end up truncated ("3:00:…") or wrapped instead of both
            // segments shrinking uniformly.
            //
            // `.footnote`, not `.subheadline`: a fixed, shared base size across every stat item is
            // deliberate here, not just a smaller default. `.minimumScaleFactor` only shrinks a
            // `Text` that doesn't fit its *own* allotted space, independently of its siblings — a
            // short value like Load's "48" never needs to shrink, while a longer one like
            // Distance's "12.3 km +8%" does, so at `.subheadline` the two ended up visibly
            // different sizes in the same row. `.footnote` comfortably fits realistic values
            // without shrinking in the common case, so every item renders at the same size instead
            // of each independently deciding its own; `.minimumScaleFactor` stays only as a safety
            // net for the rare value that's still too wide even at this smaller base.
            Text("\(value) \(percentText)")
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// `changeFraction`'s percentage, or "+∞%" when the previous week had nothing to compare
    /// against (``WeekViewModel/sportStatsPages(asOf:)`` reports that as `.infinity`, not a
    /// misleadingly literal "+0%") — any growth off a zero base is an unbounded increase, not a 0%
    /// one; a fraction that's neither finite nor infinite doesn't occur here (the underlying totals
    /// are never negative), so this only has the two cases to handle.
    private func percentString(_ changeFraction: Double) -> String {
        changeFraction.isFinite ? changeFraction.formatted(Self.percentFormat) : "+∞%"
    }
}
