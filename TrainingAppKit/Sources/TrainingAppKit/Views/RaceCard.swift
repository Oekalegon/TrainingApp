import SwiftUI
import TrainingCore

/// A race, rendered as a card in the timeline between weekday rows, laid out like `ActivityCard`'s
/// headline: where the activity card shows its coloured intensity circle, this shows the race's
/// priority as a lettered circle (A primary, B secondary, C tertiary), then a flag icon and the
/// race's name. Not tappable — there's no race detail sheet yet.
struct RaceCard: View {
    let race: Race

    var body: some View {
        HStack(spacing: TimelineCardStyle.iconSpacing) {
            Image(systemName: race.priority.markerSymbolName)
                .foregroundStyle(.primary)
                .frame(width: TimelineCardStyle.intensityMarkerWidth)
                .accessibilityHidden(true)
            Image(systemName: "flag.checkered")
                .foregroundStyle(.primary)
                .frame(width: TimelineCardStyle.iconWidth)
                .accessibilityHidden(true)
            Text(race.name)
                .bold()
                .foregroundStyle(.primary)
            Spacer()
        }
        .font(.subheadline)
        .padding(TimelineCardStyle.contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TimelineCardStyle.background)
        .clipShape(RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(race.priority.displayName) race: \(race.name)")
    }
}
