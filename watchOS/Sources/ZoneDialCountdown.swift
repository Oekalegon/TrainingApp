import SwiftUI

/// The top row of the zone dial (WATCH-118): the time or distance left in the step in white, and to
/// the right of it which interval it is, such as "5/12", when the step is in a repeat.
struct ZoneDialCountdown: View {
    /// What is left of the step, such as "0:52", or "Open".
    let remaining: String
    /// "5/12", or `nil` outside a repeat, when nothing is shown.
    let interval: String?
    /// What the countdown counts, "STEP TIME" or "STEP DISTANCE", set under "REMAINING" beside it; `nil` for an open step, which has none.
    let remainingKind: String?

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
            Text(remaining)
                .font(RunMetricStyle.valueFont)
                .lineLimit(1).minimumScaleFactor(0.5)
                // The digits have no descenders: the row is shorter than the text's own line.
                .padding(.vertical, -RunMetricStyle.valueSize * 0.14)
            if let remainingKind {
                RunMetricStyle.caption("REMAINING", remainingKind)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            if let interval {
                Text(interval)
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
}
