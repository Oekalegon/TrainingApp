import SwiftUI

/// The total workout time of the zone dial (WATCH-118), with its hours, in the same size and font as
/// the step's countdown.
struct ZoneDialTotalTime: View {
    /// Such as "0:24:15".
    let text: String
    let timerSize: Double

    var body: some View {
        Text(text)
            .font(.system(size: timerSize, weight: .semibold).width(.condensed).monospacedDigit())
            .lineLimit(1).minimumScaleFactor(0.5)
            // The digits have no descenders: the row is shorter than the text's own line.
            .padding(.vertical, -timerSize * 0.23)
    }
}
