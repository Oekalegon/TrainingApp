import Foundation
import TrainingWatchKit

/// Ready-made run screens (WATCH-137): a combination of metrics and widgets for one purpose, picked in the editor as
/// the starting point of a screen and then changed like any other. Items are listed top to bottom, the most
/// important last (it is the one at the bottom of the watch's screen, where the eye goes first, and the one a smaller
/// watch keeps).
public enum StandardScreens {
    /// One ready-made screen.
    public struct Template: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        /// What the screen is for, in a line.
        public let detail: String
        public let systemImage: String
        public let items: [RunScreenItem]

        /// The units the items take.
        public var units: Int { items.reduce(0) { $0 + $1.height } }

        /// Whether the screen has an item that means something only in a planned workout's steps, so a free run
        /// leaves it out.
        public var isOnlyInWorkouts: Bool { items.contains(where: \.requiresSteps) }

        /// The items and the room they take, with a note for a screen only planned workouts can show: the line
        /// under the screen's name in the picker.
        public var summary: String {
            let names = items.map(\.title).joined(separator: ", ")
            let note = isOnlyInWorkouts ? " Planned workouts only." : ""
            return "\(names). \(units) of \(RunScreen.capacity) units.\(note)"
        }
    }

    /// Every standard screen, in the order the editor lists them: for any run first, then for planned workouts.
    public static let all: [Template] = [
        Template(
            id: "easy-run", title: "Easy Run", detail: "Time, distance, pace and heart rate with the zones",
            systemImage: "figure.run",
            items: [.metric(.totalTime), .metric(.distance), .metric(.currentPace), .metric(.heartRate), .widget(.zoneBar)]),
        Template(
            id: "long-run", title: "Long Run", detail: "Time, distance, average pace and heart rate, and the battery",
            systemImage: "figure.walk",
            items: [.metric(.totalTime), .metric(.distance), .metric(.averagePace), .metric(.heartRate), .widget(.battery)]),
        Template(
            id: "race", title: "Race", detail: "Time, distance, both paces and heart rate",
            systemImage: "flag.checkered",
            items: [.metric(.totalTime), .metric(.distance), .metric(.averagePace), .metric(.currentPace), .metric(.heartRate)]),
        Template(
            id: "splits", title: "Splits", detail: "The pace of this and the last kilometre or mile, and how far into this one",
            systemImage: "arrow.left.and.right",
            items: [
                .metric(.totalTime), .metric(.distance), .span(.distance, .split),
                .measure(.pace, .average, .lastSplit), .measure(.pace, .average, .split), .metric(.currentPace),
            ]),
        Template(
            id: "form", title: "Running Form", detail: "Cadence, stride, ground contact time, vertical oscillation and power; most need a recent Apple Watch",
            systemImage: "figure.run.circle",
            items: [
                .measure(.runningPower, .current, .run), .measure(.verticalOscillation, .current, .run),
                .measure(.groundContactTime, .current, .run), .measure(.strideLength, .current, .run),
                .measure(.cadence, .current, .run), .metric(.heartRate),
            ]),
        Template(
            id: "climb", title: "Climb", detail: "Altitude, climb, grade, pace and heart rate",
            systemImage: "mountain.2",
            items: [
                .metric(.altitude), .metric(.elevationGain), .metric(.grade), .metric(.distance),
                .metric(.currentPace), .metric(.heartRate),
            ]),
        Template(
            id: "zones", title: "Heart Rate Zones", detail: "Time in each zone, time in this zone and heart rate",
            systemImage: "heart.text.square",
            items: [
                .metric(.totalTime), .metric(.timeInZone), .metric(.timeSinceZoneEntry), .widget(.zoneHistogram),
                .metric(.heartRate),
            ]),
        Template(
            id: "intervals-heart-rate", title: "Intervals by Heart Rate",
            detail: "The step, what is left of it, the pace, and the heart rate against its zone",
            systemImage: "timer",
            items: [.metric(.stepNumber), .widget(.stepCountdown), .metric(.currentPace), .widget(.zoneBar), .metric(.heartRate)]),
        Template(
            id: "intervals-pace", title: "Intervals by Pace",
            detail: "The step, what is left of it, the pace against its target, and the heart rate",
            systemImage: "speedometer",
            items: [.metric(.stepNumber), .widget(.stepCountdown), .widget(.paceBar), .metric(.currentPace), .metric(.heartRate)]),
        Template(
            id: "workout-progress", title: "Workout Progress",
            detail: "The step, the time into it, the time left and when the workout ends",
            systemImage: "list.number",
            items: [.metric(.stepNumber), .metric(.stepTime), .metric(.stepDistance), .metric(.timeRemaining), .metric(.finishTime), .metric(.heartRate)]),
    ]
}

extension RunScreenSetDraft {
    /// Adds a screen with the items of a standard screen (WATCH-137), which the athlete can then change.
    /// - Returns: The new screen's id.
    @discardableResult
    public mutating func addScreen(from template: StandardScreens.Template) -> String {
        let screen = RunScreen(id: UUID().uuidString, items: template.items, name: template.title)
        screens.append(screen)
        return screen.id
    }
}
