import SwiftUI

/// The heart rate row of the zone dial (WATCH-118): the heart rate in bpm at the left and the heart
/// rate's place in the zones at the right, both values in the state's colour (white, blue or red) and
/// their words ("BPM", "ZONE") small, in the fonts of `RunMetricStyle` and in the secondary colour.
struct ZoneDialHeartRate: View {
    /// The heart rate, or `nil` without a reading.
    let heartRate: Double?
    /// The place in the zones, such as "2.3" or "<1", or `nil` without a reading or zones.
    let zoneValue: String?
    /// White in the target, blue below it, red above it.
    let color: Color

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
                Text(heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                    .font(RunMetricStyle.valueFont)
                    .foregroundStyle(color)
                Text("BPM").font(RunMetricStyle.unitFont).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
                Text("ZONE").font(RunMetricStyle.unitFont).foregroundStyle(.secondary)
                Text(zoneValue ?? "--")
                    .font(RunMetricStyle.valueFont)
                    .foregroundStyle(color)
            }
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        // The digits have no descenders: the row is shorter than the text's own line, as on the standard screen.
        .padding(.vertical, -RunMetricStyle.valueSize * 0.14)
    }
}
