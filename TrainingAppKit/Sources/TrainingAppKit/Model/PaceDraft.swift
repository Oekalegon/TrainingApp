import Foundation
import TrainingCore

/// What the athlete types into the threshold-pace sheet (MVP2-132): the date it takes effect and the
/// pace as minutes and seconds per kilometer.
struct PaceDraft: Equatable {
    /// The first day the pace applies.
    var effectiveDate: Date
    var minutes: Int
    var seconds: Int

    /// Starts from `paceModel`'s threshold pace, or 5:00 /km when there's none.
    ///
    /// - Parameters:
    ///   - paceModel: The model to prefill from, if any.
    ///   - effectiveDate: The date the new entry would take effect.
    init(prefilling paceModel: PaceModel?, effectiveDate: Date) {
        self.effectiveDate = effectiveDate
        let total = Int((paceModel?.thresholdPaceSecondsPerKilometer ?? 300).rounded())
        minutes = total / 60
        seconds = total % 60
    }

    /// The pace in seconds per kilometer.
    var thresholdPaceSecondsPerKilometer: Double {
        Double(minutes * 60 + seconds)
    }

    /// Why the pace can't be saved, or `nil` when it can.
    var validationMessage: String? {
        guard (0..<60).contains(seconds) else { return "Seconds should be between 0 and 59." }
        guard (120...1200).contains(minutes * 60 + seconds) else {
            return "Threshold pace should be between 2:00 and 20:00 per kilometer."
        }
        return nil
    }

    /// The pace model to record: `current` with this threshold pace, keeping its zone multipliers.
    ///
    /// - Parameter current: The model in effect, whose per-zone multipliers carry over.
    func paceModel(basedOn current: PaceModel) -> PaceModel {
        PaceModel(
            thresholdPaceSecondsPerKilometer: thresholdPaceSecondsPerKilometer,
            zonePaceMultipliers: current.zonePaceMultipliers
        )
    }
}
