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
            // The charge at the left and, in a planned workout, the forecast at the right, in the forecast's colour.
            HStack(spacing: 6) {
                Text("BATTERY \(battery.percentText)").foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let projection {
                    Text(projection.text).foregroundStyle(projection.verdict.color)
                }
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .lineLimit(1).minimumScaleFactor(0.85)
            .accessibilityHidden(true)
            BatteryBar(battery, tint: projection?.verdict.color)
        }
        .padding(.horizontal, inset)
        .padding(.top, 2)
        .padding(.bottom, bottomInset)
    }
}
