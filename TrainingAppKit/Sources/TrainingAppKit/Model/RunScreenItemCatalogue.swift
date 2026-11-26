import Foundation
import TrainingWatchKit

/// What the athlete can put on a run screen, by group, with the words for it (WATCH-134, WATCH-135 will
/// grow it): the picker browses the groups and searches the names.
public enum RunScreenItemCatalogue {
    /// One group of the picker, named after the main metric.
    public struct Group: Equatable, Sendable, Identifiable {
        public var id: String { title }
        public let title: String
        public let items: [RunScreenItem]
    }

    /// Every group, in the order the picker shows them.
    public static let groups: [Group] = [
        Group(title: "Heart Rate", items: [
            .metric(.heartRate), .metric(.averageHeartRate), .metric(.maxHeartRate), .widget(.zoneBar), .widget(.zoneHistogram),
        ]),
        Group(title: "Pace", items: [.metric(.currentPace), .metric(.averagePace)]),
        Group(title: "Distance and Time", items: [.metric(.distance), .metric(.totalTime), .metric(.clock)]),
        Group(title: "Elevation and Grade", items: [.metric(.altitude), .metric(.elevationGain), .metric(.grade)]),
        Group(title: "Workout Step", items: [.widget(.stepCountdown), .metric(.timeRemaining), .metric(.finishTime)]),
        Group(title: "Watch", items: [.widget(.battery)]),
    ]

    /// The groups with the items whose name (or group) contains `query`, ignoring case and accents; all of
    /// them for an empty query, and no empty group.
    public static func groups(matching query: String) -> [Group] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groups }
        func matches(_ text: String) -> Bool { text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        return groups.compactMap { group in
            let items = matches(group.title) ? group.items : group.items.filter { matches($0.title) }
            return items.isEmpty ? nil : Group(title: group.title, items: items)
        }
    }
}

extension RunScreenItem {
    /// The item's name in the editor.
    public var title: String {
        switch self {
        case .metric(let metric):
            switch metric {
            case .totalTime: "Total Time"
            case .distance: "Distance"
            case .heartRate: "Heart Rate and Zone"
            case .currentPace: "Current Pace"
            case .averagePace: "Average Pace"
            case .clock: "Time of Day"
            case .averageHeartRate: "Average Heart Rate"
            case .maxHeartRate: "Highest Heart Rate"
            case .altitude: "Altitude"
            case .elevationGain: "Elevation Gain"
            case .grade: "Grade"
            case .timeRemaining: "Time Left"
            case .finishTime: "Finish Time"
            }
        case .widget(let widget):
            switch widget {
            case .zoneBar: "Zone Bar"
            case .battery: "Battery and Forecast"
            case .stepCountdown: "Step Countdown"
            case .zoneHistogram: "Time in Zones"
            }
        }
    }

    /// A line under the name saying what it shows.
    public var detail: String {
        switch self {
        case .metric(.totalTime): "The workout's time so far"
        case .metric(.distance): "How far the run has gone"
        case .metric(.heartRate): "The heart rate and its place in the zones"
        case .metric(.currentPace): "The pace over the last 20 seconds"
        case .metric(.averagePace): "The pace of the whole run"
        case .metric(.clock): "The time of day"
        case .metric(.averageHeartRate): "The mean heart rate of the run so far"
        case .metric(.maxHeartRate): "The highest heart rate of the run so far"
        case .metric(.altitude): "The altitude from the GPS"
        case .metric(.elevationGain): "How far the run has climbed"
        case .metric(.grade): "The slope of the last 50 metres or so, in percent"
        case .metric(.timeRemaining): "The time left in the workout, counting distances at the current pace; planned workouts only"
        case .metric(.finishTime): "The time of day the workout should end; planned workouts only"
        case .widget(.zoneBar): "All the zones on one line with the heart rate and the step's target"
        case .widget(.battery): "The watch's charge and how much is left at the end"
        case .widget(.stepCountdown): "Time or distance left in the step; planned workouts only"
        case .widget(.zoneHistogram): "How long the run has spent in each zone"
        }
    }

    /// The SF Symbol of the item.
    public var systemImage: String {
        switch self {
        case .metric(.totalTime): "clock"
        case .metric(.distance): "point.topleft.down.to.point.bottomright.curvepath"
        case .metric(.heartRate): "heart.fill"
        case .metric(.currentPace), .metric(.averagePace): "speedometer"
        case .metric(.clock): "clock.fill"
        case .metric(.averageHeartRate), .metric(.maxHeartRate): "heart"
        case .metric(.altitude), .metric(.elevationGain): "mountain.2"
        case .metric(.grade): "angle"
        case .metric(.timeRemaining): "hourglass"
        case .metric(.finishTime): "flag.checkered"
        case .widget(.zoneBar): "chart.bar.xaxis"
        case .widget(.battery): "battery.75percent"
        case .widget(.stepCountdown): "timer"
        case .widget(.zoneHistogram): "chart.bar.fill"
        }
    }
}
