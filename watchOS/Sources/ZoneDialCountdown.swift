import SwiftUI

/// The top row of the zone dial (WATCH-118): the time or distance left in the step in yellow, and to
/// the right of it which interval it is, such as "5/12", when the step is in a repeat.
struct ZoneDialCountdown: View {
    /// What is left of the step, such as "0:52", or "Open".
    let remaining: String
    /// "5/12", or `nil` outside a repeat, when nothing is shown.
    let interval: String?
    let timerSize: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(remaining)
                .font(.system(size: timerSize, weight: .semibold).width(.condensed).monospacedDigit())
                .foregroundStyle(.yellow)
                .lineLimit(1).minimumScaleFactor(0.5)
                // The digits have no descenders: the row is shorter than the text's own line.
                .padding(.vertical, -timerSize * 0.23)
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
