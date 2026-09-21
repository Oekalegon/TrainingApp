import SwiftUI

/// Constants and formatters shared by `ActivityCard` and `PlannedActivityCard` (design doc §2.1,
/// MVP1-41/MVP2-37), so a completed activity's filled card and a planned one's hatched card stay the
/// same shape and layout, distinguished by fill rather than by silhouette.
enum TimelineCardStyle {
    /// Corner radius of both cards.
    static let cornerRadius: CGFloat = 12
    /// Inner padding of both cards. Also the padding `DayActivitiesSection`'s time label matches, so
    /// the label and a card's headline line land at the same y (deterministic matched offsets, not
    /// `.firstTextBaseline`, given the card's own padding/background/Button nesting).
    static let contentPadding: CGFloat = 12
    /// Fixed so the icon's actual glyph width (which varies per sport) doesn't change where the
    /// second line's indent lands — the second line aligns to this width plus `iconSpacing`, not to
    /// the icon's own measured size.
    static let iconWidth: CGFloat = 22
    static let iconSpacing: CGFloat = 8

    static let loadFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
    static let measurementFormat = Measurement<UnitLength>.FormatStyle.measurement(width: .abbreviated)

    /// "1:30:00" — a duration as H:MM:SS, as both cards show it.
    static func durationText(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond))
    }

    /// "8 km" — a distance in the user's units, abbreviated, as both cards show it.
    static func distanceText(meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters).formatted(measurementFormat)
    }

    /// "1 hour, 30 minutes" — for VoiceOver.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    /// "8 kilometers" — for VoiceOver.
    static func spokenDistance(meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .wide))
    }

    /// The cards' own background — "elevated" relative to `weekViewBackground` (white in light mode,
    /// a dark elevated grey in dark mode), the opposite direction from `unhighlightedPillBackground`'s
    /// "recessed" pills/timeline, so a card reads as the most prominent surface in the day list.
    #if os(iOS)
    static let background = Color(.secondarySystemGroupedBackground)
    #else
    static let background = Color.white
    #endif
}
