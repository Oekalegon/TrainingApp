import Foundation
import TrainingCore

extension AthleteProfile {
    /// A minimal athlete for tests that don't care about biometrics, just identity/calendar
    /// defaults — mirrors TrainingKit's own `AthleteProfile.fixture()` test helper.
    static func fixture(
        weekStartsOn: Weekday = .monday,
        timeZoneIdentifier: String = "UTC",
        restingHeartRateBPM: Double? = nil,
        maxHeartRateBPM: Double? = nil
    ) -> AthleteProfile {
        let heartRateZoneHistory: [HeartRateZoneSettings]
        if let restingHeartRateBPM, let maxHeartRateBPM {
            heartRateZoneHistory = [
                HeartRateZoneSettings(
                    effectiveDate: .distantPast,
                    restingHeartRateBPM: restingHeartRateBPM,
                    maxHeartRateBPM: maxHeartRateBPM
                )
            ]
        } else {
            heartRateZoneHistory = []
        }
        return AthleteProfile(
            sex: .unspecified,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 300),
            timeZone: TimeZone(identifier: timeZoneIdentifier)!,
            weekStartsOn: weekStartsOn,
            heartRateZoneHistory: heartRateZoneHistory
        )
    }
}
