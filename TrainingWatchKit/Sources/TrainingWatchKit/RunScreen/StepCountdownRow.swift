import SwiftUI

/// The top row of the zone dial (WATCH-118): the time or distance left in the step in white, and to
/// the right of it which interval or step it is, such as "REP 5/12" or "2/6", in the primary colour.
/// A short caption ("STEP TIME") sits beside the countdown, and goes when the row is too narrow for both: the
/// countdown matters more and keeps its size.
public struct StepCountdownRow: View {
    /// What is left of the step, such as "0:52", or "Open".
    let remaining: String
    /// Where the step is: "REP 5/12" in a repeat, "2/6" outside one.
    let place: ZoneDialText.Place
    /// What the countdown counts, "TIME" or "DIST", set under "STEP" beside it; `nil` for an open step, which has none.
    let remainingKind: String?

    public var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
            // The countdown matters most: it keeps its size, and the caption goes when both don't fit.
            // Only when the countdown is too wide on its own does it shrink.
            ViewThatFits(in: .horizontal) {
                countdown(withCaption: true).fixedSize(horizontal: true, vertical: false)
                countdown(withCaption: false)
            }
            Spacer(minLength: 2)
            HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
                if place.isRepeat {
                    Text("REP").font(RunMetricStyle.captionFont).foregroundStyle(.secondary)
                }
                Text(place.text)
                    .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
            }
            .lineLimit(1)
            // The place and its captions keep their size, the same as the captions of the other metrics.
            .layoutPriority(1)
        }
    }

    /// The countdown, with "STEP / TIME" beside it when `withCaption` and there is a kind to say.
    private func countdown(withCaption: Bool) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
            Text(remaining)
                .font(RunMetricStyle.valueFont)
                .lineLimit(1).minimumScaleFactor(0.5)
                // The digits have no descenders: the row is shorter than the text's own line.
                .padding(.vertical, -RunMetricStyle.valueSize * 0.14)
            if withCaption, let remainingKind {
                RunMetricStyle.caption("STEP", remainingKind, shrinks: false)
                    .accessibilityHidden(true)
            }
        }
    }
}
