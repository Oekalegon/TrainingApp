import Testing
import TrainingCore
@testable import TrainingAppKit

@Suite("TrainingAppEnvironment")
struct TrainingAppEnvironmentTests {
    @Test("placeholderAthlete() is a usable, if blank, profile")
    func placeholderAthleteIsUsable() {
        let athlete = TrainingAppEnvironment.placeholderAthlete()

        #expect(athlete.sex == .unspecified)
        #expect(athlete.heartRateZoneHistory.isEmpty)
        #expect(athlete.name.isEmpty)
    }
}
