import Foundation
import TrainingCore

/// Drives the read-only athlete screens (design doc §2.3), the Athlete tab's list and the screens it
/// opens (MVP2-123): everything here comes straight from `AthleteProfile`. Edits don't go through this
/// view model; they're `WeekViewModel`'s (`WeekViewModel+AthleteEditing`, MVP2-132).
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

    /// The athlete's age for the Personal Information screen (MVP2-124), in whole years as of `today`
    /// in the athlete's time zone, or `nil` while no date of birth is on record.
    ///
    /// - Parameter today: The date to compute the age as of; injected for tests.
    public func ageText(asOf today: Date = .now) -> String? {
        athlete.age(asOf: today).map { "\($0)" }
    }

    /// The zone settings currently in effect, if the athlete has any on record — MVP 1 shows only
    /// this, not the full `heartRateZoneHistory` timeline.
    public var currentHeartRateZoneSettings: HeartRateZoneSettings? {
        athlete.currentHeartRateZoneSettings
    }

    /// Where the current max heart rate came from, for a caption under the Max HR row (MVP2-56):
    /// "Estimated from age", or "Measured in a workout on 24 Sep 2026". `nil` when there are no
    /// settings on record.
    ///
    /// The workout's date is the earliest entry carrying that source, which is the entry that
    /// starts at the workout itself; later entries raised to the same value share its source.
    public var maxHeartRateSourceDescription: String? {
        guard let settings = currentHeartRateZoneSettings else { return nil }
        switch settings.maxHeartRateSource {
        case .formula:
            return "Estimated from age"
        case .manual:
            let date = settings.effectiveDate.formatted(
                Date.FormatStyle(timeZone: athlete.timeZone).day().month(.abbreviated).year()
            )
            return "Set by you on \(date)"
        case .workout:
            let measuredFrom = athlete.heartRateZoneHistory
                .filter { $0.maxHeartRateSource == settings.maxHeartRateSource }
                .map(\.effectiveDate)
                .min() ?? settings.effectiveDate
            let date = measuredFrom.formatted(
                Date.FormatStyle(timeZone: athlete.timeZone).day().month(.abbreviated).year()
            )
            return "Measured in a workout on \(date)"
        }
    }

    /// Every named zone's bpm range under ``currentHeartRateZoneSettings``, in zone order
    /// (1 through 5) — empty when there are no settings on record yet, or when the current
    /// method can't resolve a zone at all (`.lactateThreshold` with no LTHR set, matching
    /// `HeartRateZoneModel.zoneBPMRange(_:)`'s own `nil` cases).
    public var heartRateZoneRanges: [HeartRateZoneRange] {
        guard let settings = currentHeartRateZoneSettings else { return [] }
        let model = HeartRateZoneModel(settings: settings)
        return HeartRateZone.allCases.compactMap { zone in
            guard let bpmRange = model.zoneBPMRange(zone.rawValue) else { return nil }
            return HeartRateZoneRange(zone: zone, bpmRange: bpmRange)
        }
    }

    /// The date to offer when the athlete edits a history entry dated `entryDate`: the entry's own,
    /// except for one effective since the beginning of time (a profile stored before the history was
    /// dated), which has no date worth showing, so editing it records a new entry from `today`.
    ///
    /// - Parameters:
    ///   - entryDate: The entry's effective date.
    ///   - today: The date to use instead; injected for tests.
    public static func editingDate(for entryDate: Date, asOf today: Date = .now) -> Date {
        entryDate == .distantPast ? today : entryDate
    }

    /// Every heart-rate settings entry, newest first, for the history list (MVP2-132).
    public var heartRateHistory: [HeartRateZoneSettings] {
        athlete.heartRateZoneHistory.sorted { $0.effectiveDate > $1.effectiveDate }
    }

    /// Every pace entry, newest first, for the history list (MVP2-132).
    public var paceHistory: [PaceSettings] {
        athlete.paceHistory.sorted { $0.effectiveDate > $1.effectiveDate }
    }

    /// The Tanaka estimate of maximum heart rate for the athlete's age on `today`, if a date of birth
    /// is on record.
    ///
    /// - Parameter today: The date to estimate as of; injected for tests.
    public func ageEstimatedMaxHeartRate(asOf today: Date = .now) -> Double? {
        athlete.dateOfBirth.map { TanakaHRMaxEstimator().estimatedMaxHeartRateBPM(dateOfBirth: $0, asOf: today) }
    }

    /// The age estimate to offer the athlete as a new maximum heart rate (MVP2-132), or `nil` when
    /// there's nothing to offer: it's never applied on its own, so the athlete decides.
    ///
    /// Offered only while the current maximum is itself an estimate and the new one differs by at
    /// least ``AthleteProfile/heartRateChangeToleranceBPM``; a maximum the athlete entered or a
    /// workout measured isn't compared with a formula.
    ///
    /// - Parameter today: The date to estimate as of; injected for tests.
    public func offeredMaxHeartRateEstimate(asOf today: Date = .now) -> Double? {
        guard let current = currentHeartRateZoneSettings, current.maxHeartRateSource == .formula,
              let estimate = ageEstimatedMaxHeartRate(asOf: today),
              abs(estimate - current.maxHeartRateBPM) >= AthleteProfile.heartRateChangeToleranceBPM
        else { return nil }
        return estimate.rounded()
    }

    /// Threshold pace as minutes:seconds per kilometer, e.g. "4:00 /km".
    public var thresholdPaceText: String {
        Self.paceText(athlete.paceModel.thresholdPaceSecondsPerKilometer)
    }

    /// `secondsPerKilometer` as minutes:seconds per kilometer, e.g. "4:00 /km".
    ///
    /// - Parameter secondsPerKilometer: The pace to format.
    public static func paceText(_ secondsPerKilometer: Double) -> String {
        let totalSeconds = Int(secondsPerKilometer.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }
}
