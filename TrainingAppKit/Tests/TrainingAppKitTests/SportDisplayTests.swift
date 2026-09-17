import Testing
import TrainingCore
@testable import TrainingAppKit

@Suite("Sport+Display")
struct SportDisplayTests {
    @Test("supportsLowIntensityTrainingSplit is true only for the running family and cycling")
    func supportsLowIntensityTrainingSplitScopesToDeliberateHardEasyTrainingSports() {
        let expectedTrue: Set<Sport> = [.running, .indoorRunning, .outdoorRunning, .cycling]
        let allCases: [Sport] = [
            .running, .indoorRunning, .outdoorRunning, .cycling, .swimming, .strength,
            .coreStrengthTraining, .walking, .rowing, .hiking, .other("Skiing"),
        ]

        for sport in allCases {
            #expect(sport.supportsLowIntensityTrainingSplit == expectedTrue.contains(sport))
        }
    }
}
