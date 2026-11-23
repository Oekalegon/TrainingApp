import SwiftUI

/// The heart rate row of the zone dial (WATCH-118): the heart rate in bpm at the left and the heart
/// rate's place in the zones at the right, both values in the state's colour (white, blue or red) and
/// their words ("BPM", "Zone") small and in the secondary colour.
struct ZoneDialHeartRate: View {
    /// The heart rate, or `nil` without a reading.
    let heartRate: Double?
    /// The place in the zones, such as "2.3" or "<1", or `nil` without a reading or zones.
    let zoneValue: String?
    /// White in the target, blue below it, red above it.
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                    .font(.system(size: 32, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
                Text("BPM").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Zone").font(.system(size: 14)).foregroundStyle(.secondary)
                Text(zoneValue ?? "--")
                    .font(.system(size: 32, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
            }
        }
        .lineLimit(1).minimumScaleFactor(0.7)
    }
}
