import Foundation
import TrainingCore

extension AthleteProfile {
    /// A minimal athlete for tests that don't care about biometrics, just identity/calendar
    /// defaults — mirrors TrainingKit's own `AthleteProfile.fixture()` test helper.
    static func fixture(
        weekStartsOn: Weekday = .monday,
        timeZoneIdentifier: String = "UTC"
    ) -> AthleteProfile {
        AthleteProfile(
            sex: .unspecified,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 300),
            timeZone: TimeZone(identifier: timeZoneIdentifier)!,
            weekStartsOn: weekStartsOn,
            heartRateZoneHistory: []
        )
    }
}
