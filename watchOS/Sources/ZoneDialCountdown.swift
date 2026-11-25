import SwiftUI

/// The top row of the zone dial (WATCH-118): the time or distance left in the step in white, and to
/// the right of it which interval or step it is, such as "REP 5/12" or "2/6", in the primary colour.
struct ZoneDialCountdown: View {
    /// What is left of the step, such as "0:52", or "Open".
    let remaining: String
    /// "5/12" in a repeat or "2/6", the step's place, outside one (`ZoneDialText.placeFraction`).
    let interval: String?
    /// Whether `interval` is an interval of a repeat: "REP" is then set small before it.
    let isRepeat: Bool
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
                HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
                    if isRepeat {
                        Text("REP").font(RunMetricStyle.captionFont).foregroundStyle(.secondary)
                    }
                    Text(interval)
                        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                // The place keeps its size: the countdown and its caption give way first.
                .layoutPriority(1)
            }
        }
    }
}
