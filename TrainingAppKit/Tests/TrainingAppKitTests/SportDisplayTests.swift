import Testing
import TrainingCore
@testable import TrainingAppKit

@Suite("Sport+Display")
struct SportDisplayTests {
    @Test("supportsLowIntensityTrainingSplit is true only for running and cycling")
    func supportsLowIntensityTrainingSplitScopesToDeliberateHardEasyTrainingSports() {
        let expectedTrue: Set<Sport> = [.running, .cycling]
        let allCases: [Sport] = [
            .running, .cycling, .swimming, .strength,
            .coreStrengthTraining, .walking, .rowing, .hiking, .other("Skiing"),
        ]

        for sport in allCases {
            #expect(sport.supportsLowIntensityTrainingSplit == expectedTrue.contains(sport))
        }
    }

    @Test("a venue is named after its place and surface")
    func venueDisplayNames() {
        #expect(Venue.indoor(.treadmill).displayName == "Treadmill")
        #expect(Venue.outdoor(.trail).displayName == "Trail")
        #expect(Venue.outdoor(nil).displayName == "Outdoors")
        #expect(Sport.running.displayName(venue: .outdoor(.trail)) == "Running · Trail")
        #expect(Sport.running.displayName(venue: nil) == "Running")
    }
}
