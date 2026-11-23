import SwiftUI
import TrainingWatchKit

/// The battery at the bottom of the zone dial (WATCH-118, WATCH-119): "BATTERY 67%" in small type and
/// in a planned workout the forecast after it ("~44% AT END", coloured by how that rates), and under it
/// the bar, which takes the colour of the forecast when there is one. Both are in from the sides, where
/// the screen's corners round off.
struct ZoneDialBattery: View {
    let battery: BatteryDisplay
    /// What the battery will be at the end of the workout, or `nil` when that isn't known.
    let projection: BatteryProjection?
    /// How far the line and the bar are in from the sides.
    let inset: Double
    /// The room kept free under the bar, for the page indicator.
    let bottomInset: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Text("BATTERY \(battery.percentText)").foregroundStyle(.secondary)
                if let projection {
                    Text("  ·  ").foregroundStyle(.secondary)
                    Text(projection.text).foregroundStyle(projection.verdict.color)
                }
            }
            .font(.system(size: 10))
            .lineLimit(1).minimumScaleFactor(0.7)
            .accessibilityHidden(true)
            BatteryBar(battery, tint: projection?.verdict.color)
        }
        .padding(.horizontal, inset)
        .padding(.top, 12)
        .padding(.bottom, bottomInset)
    }
}
