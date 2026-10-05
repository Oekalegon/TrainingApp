import Foundation

/// The "~" that marks an estimated value wherever the app shows one (MVP2-8): a planned workout's
/// TRIMP, a distance forecast from the athlete's paces, a load scored from perceived effort, a
/// projected day's fitness figures. Measured values and the targets a plan sets (a time step's
/// duration, a distance step's distance, a load the athlete typed in) are shown plainly, so the
/// marker only appears where a model made the number up.
///
/// VoiceOver says "estimated" instead, since a spoken "tilde" is easy to miss.
enum EstimateMarker {
    /// The marker itself, put directly in front of the value: "~65".
    static let symbol = "~"

    /// `value` with the marker in front when `isEstimated`.
    static func text(_ value: String, isEstimated: Bool) -> String {
        isEstimated ? symbol + value : value
    }

    /// `value` with "estimated " in front when `isEstimated`, for VoiceOver.
    static func spoken(_ value: String, isEstimated: Bool) -> String {
        isEstimated ? "estimated " + value : value
    }

    /// `text` as VoiceOver should read it: a leading marker becomes "estimated ", so "~65" reads
    /// "estimated 65". For a view that shows a ``text(_:isEstimated:)`` result without building its
    /// own label.
    static func spokenForm(of text: String) -> String {
        guard text.hasPrefix(symbol) else { return text }
        return "estimated " + text.dropFirst(symbol.count)
    }
}
