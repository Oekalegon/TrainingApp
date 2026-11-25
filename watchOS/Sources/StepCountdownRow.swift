import SwiftUI
import TrainingWatchKit

/// The top row of the zone dial (WATCH-118): the time or distance left in the step in white, and to
/// the right of it which interval or step it is, such as "REP 5/12" or "2/6", in the primary colour.
struct StepCountdownRow: View {
    /// What is left of the step, such as "0:52", or "Open".
    let remaining: String
    /// Where the step is: "REP 5/12" in a repeat, "2/6" outside one.
    let place: ZoneDialText.Place
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
                RunMetricStyle.caption("REMAINING", remainingKind, shrinks: false)
                    .accessibilityHidden(true)
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
            // The place and its captions keep their size, the same as the captions of the other metrics:
            // only the countdown gives way when the row is short of room.
            .layoutPriority(1)
        }
    }
}
