import Foundation
import TrainingCore

/// Drives the read-only athlete account screen (design doc §2.3): everything here comes straight
/// from `AthleteProfile` — no editing, no write path through `TrainingModel` exists yet.
///
/// Immutable after creation, like `ActivityDetailViewModel` — a plain struct, not an `@Observable`
/// class.
public struct AthleteViewModel {
    public let athlete: AthleteProfile

    public init(athlete: AthleteProfile) {
        self.athlete = athlete
    }

    /// The name to display, falling back to a generic label when the athlete hasn't set one yet
    /// (e.g. before the first HealthKit import pre-fills it).
    public var displayName: String {
        athlete.name.isEmpty ? "Athlete" : athlete.name
    }

    /// A one- or two-letter monogram derived from ``displayName`` — the avatar shown in place of
    /// a photo (design doc §2.3: no iCloud/Contacts photo lookup in MVP 1).
    public var initials: String {
        let words = displayName.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// The zone settings currently in effect, if the athlete has any on record — MVP 1 shows only
    /// this, not the full `heartRateZoneHistory` timeline.
    public var currentHeartRateZoneSettings: HeartRateZoneSettings? {
        athlete.currentHeartRateZoneSettings
    }

    /// Threshold pace as minutes:seconds per kilometer, e.g. "4:00 /km".
    public var thresholdPaceText: String {
        let totalSeconds = Int(athlete.paceModel.thresholdPaceSecondsPerKilometer.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }
}
