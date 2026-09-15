import Foundation

/// The metric detail chart's own swipe-to-pan state (MVP1-45) — a plain, non-`View` type so the
/// pan/clamp/buffer math it owns can be constructed and asserted on directly in
/// `TrainingAppKitTests`, rather than living as private methods on `MetricDetailView` where nothing
/// outside SwiftUI's own gesture machinery could ever exercise them.
///
/// `MetricDetailView` holds one of these as `@State`, driving it from a `DragGesture` and reading
/// `anchorDate`/`loadedRange` back out to build `periodRange`/`visibleRange`. `period` and
/// `calendar` are never stored here — both come from `MetricDetailView` itself (`period` is a
/// `Binding` shared with `WeekView`), so every method takes them as parameters instead of risking a
/// stale copy drifting out of sync with the view's own.
struct ChartPanState: Equatable {
    /// The center date `ChartPeriod.range(around:)` is built around — separate from the tapped
    /// day, which stays fixed to that day's own header value/date/zone no matter how far the chart
    /// itself is panned.
    var anchorDate: Date
    /// The range currently loaded into the chart's own data buffer — panning is clamped so the
    /// window it produces never steps outside this, since there's no data beyond it to show yet.
    var loadedRange: ClosedRange<Date>
    /// The chart's own rendered width in points, captured once the chart actually lays out — lets
    /// a pan gesture convert its pixel translation into a day offset at (approximately) the
    /// chart's own pixel-per-day scale, so the plotted line/bars track the finger at roughly 1:1
    /// speed rather than lagging or overshooting it. `1` (not `0`) before the first layout pass, so
    /// dividing by it can't ever produce infinity/NaN.
    var chartWidth: CGFloat = 1

    /// A buffer three times as wide as `period`'s own range around `anchor` — one extra span's
    /// worth of history and future on top of what's actually shown, so a pan gesture has real room
    /// to move before it runs out of loaded data and has to wait on a refetch again.
    func bufferRange(around anchor: Date, period: ChartPeriod, calendar: Calendar) -> ClosedRange<Date> {
        let base = period.range(around: anchor, calendar: calendar)
        let span = base.upperBound.timeIntervalSince(base.lowerBound)
        return base.lowerBound.addingTimeInterval(-span)...base.upperBound.addingTimeInterval(span)
    }

    /// Converts a drag gesture's horizontal translation into a clamped candidate `anchorDate` —
    /// shared by the live (in-progress) and committed (drag-ended) cases so both agree on exactly
    /// where a given translation lands. Dragging right reveals the past (translation is positive,
    /// so the offset is negative — earlier), matching a plain scroll view's own "content follows
    /// the finger" feel.
    func panAnchor(for translation: CGFloat, period: ChartPeriod, calendar: Calendar) -> Date {
        guard chartWidth > 1, translation != 0 else { return anchorDate }
        let visibleRange = period.range(around: anchorDate, calendar: calendar)
        let visibleSpanDays = visibleRange.upperBound.timeIntervalSince(visibleRange.lowerBound) / 86_400
        let daysPerPoint = visibleSpanDays / Double(chartWidth)
        let dayOffset = Int((-Double(translation) * daysPerPoint).rounded())
        let candidate = calendar.date(byAdding: .day, value: dayOffset, to: anchorDate) ?? anchorDate
        return clamped(candidate, period: period, calendar: calendar)
    }

    /// Keeps `period.range(around:)` for the candidate anchor fully inside `loadedRange` — panning
    /// stops at the edge of what's actually loaded instead of revealing a blank chart beyond it.
    /// Falls back to `anchorDate` itself (refusing to move) if `loadedRange` is too narrow for
    /// `period` to fit at all — notably right after `MetricDetailView` first appears with an empty
    /// `chartContext.metrics` (nothing imported yet), when `loadedRange` is a zero-width `now...now`
    /// placeholder: panning is a no-op for the brief window until the first buffer fetch completes,
    /// rather than producing a nonsensical date.
    func clamped(_ candidate: Date, period: ChartPeriod, calendar: Calendar) -> Date {
        guard
            let earliestAllowed = calendar.date(byAdding: .day, value: period.lookbackDays, to: loadedRange.lowerBound),
            let latestAllowed = calendar.date(byAdding: .day, value: -7, to: loadedRange.upperBound),
            earliestAllowed <= latestAllowed
        else { return anchorDate }
        return min(max(candidate, earliestAllowed), latestAllowed)
    }
}
