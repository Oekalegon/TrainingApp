import Foundation
import TrainingCore

extension Race {
    /// A marathon, for tests that do not care about the distance (`Race` needs one since the TrainingKit race-distance change).
    init(name: String, date: Date, priority: RacePriority) {
        self.init(name: name, date: date, priority: priority, distanceMeters: Race.marathonDistanceMeters)
    }
}
