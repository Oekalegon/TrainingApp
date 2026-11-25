import SwiftUI

/// The total workout time of the zone dial (WATCH-118), with its hours, in the same size and font as
/// the step's countdown and every metric of the standard screen (`RunMetricStyle`).
struct ZoneDialTotalTime: View {
    /// Such as "0:24:15".
    let text: String

    var body: some View {
        Text(text)
            .font(RunMetricStyle.valueFont)
            .lineLimit(1).minimumScaleFactor(0.5)
            // The digits have no descenders: the row is shorter than the text's own line.
            .padding(.vertical, -RunMetricStyle.valueSize * 0.14)
    }
}
