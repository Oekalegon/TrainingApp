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
    /// A completed card's background tint (MVP2-43): the category colour, subdued so the card's text
    /// stays legible in light and dark mode. Fainter again when the assessment is low-confidence, so
    /// a guess doesn't read as firmly as a well-supported result.
    var tint: Color {
        category.color.opacity(confidence == .low ? 0.08 : 0.16)
    }

    /// A planned card's hatch-stripe colour: the same hue as ``tint``, stronger because thin
    /// stripes over a plain fill cover far less area than a full background does.
    var hatchTint: Color {
        category.color.opacity(confidence == .low ? 0.14 : 0.28)
    }
}
