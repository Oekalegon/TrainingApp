import SwiftUI

/// One row in a "list every zone, name + explanation" card — shared by `MetricDetailView`'s own
/// `formZoneSection` (TSB zones, MVP1-75) and `HeartRateZoneDetailView`'s `timeInZoneSection`
/// (heart-rate zones, MVP1-77/MVP1-79), so the two "here are all the zones" screens in this app use
/// one row layout rather than two copies that can drift apart. A colored swatch names which zone
/// this is; `highlightTint`, when non-`nil`, tints the whole row (e.g. the subject's own current
/// TSB zone) — `nil` for a plain row, as every heart-rate zone row is, since a whole week's HR data
/// has no single "current" zone the way a single day's TSB reading does.
struct ZoneListRow: View {
    let color: Color
    let title: String
    let explanation: String
    var highlightTint: Color?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 12, height: 12)
                // Nudges the swatch to align with the first line's cap-height, not the row's own top.
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlightTint ?? .clear)
    }
}
