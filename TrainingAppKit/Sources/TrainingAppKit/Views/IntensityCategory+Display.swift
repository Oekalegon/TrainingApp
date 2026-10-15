import SwiftUI
import TrainingCore

extension IntensityCategory {
    var displayName: String {
        switch self {
        case .veryLow: "Very low"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    /// Follows the heart-rate zone colours (recovery blue, aerobic green, tempo yellow) so an
    /// intensity reads in the same colour language as the zone charts; `.high` covers both the
    /// threshold and anaerobic zones and takes the anaerobic red.
    var color: Color {
        switch self {
        case .veryLow: HeartRateZone.recovery.color
        case .low: HeartRateZone.aerobic.color
        case .medium: HeartRateZone.tempo.color
        case .high: HeartRateZone.anaerobic.color
        }
    }
}

extension IntensityAssessment {
    /// VoiceOver text, e.g. "Intensity: high, planned".
    var accessibilityDescription: String {
        let sourceText = switch source {
        case .planned: "planned"
        case .measured: "measured"
        case .blended: "from the plan and heart rate"
        }
        return "Intensity: \(category.displayName.lowercased()), \(sourceText)"
    }
}

extension IntensityAssessment {
    /// The colour of the small intensity marker `ActivityCard`/`PlannedActivityCard` draw leading
    /// their headline row (MVP2-51) — the category colour at full strength, regardless of
    /// `confidence`; at this marker's size a fainter fill for a low-confidence assessment wasn't
    /// legible enough to be worth the earlier tinted-background design's opacity trick.
    var tint: Color {
        category.color
    }
}
