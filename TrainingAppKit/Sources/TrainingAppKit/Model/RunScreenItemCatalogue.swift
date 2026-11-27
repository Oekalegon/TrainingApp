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

        /// A part of a group: the items over one scope, or the items that have none.
        public struct Section: Equatable, Sendable, Identifiable {
            public var id: String { title ?? "" }
            /// The scope's name ("Whole Run", "This Step"…), or `nil` for the items that have no scope.
            public let title: String?
            public let items: [RunScreenItem]

            /// The header in a group's own view: the scope's name, or "Metrics" for the items with none (the group's
            /// name is already the title of the view).
            public var displayTitle: String { title ?? "Metrics" }
        }

        /// The items in parts by scope, so a long group is browsed one scope at a time: first the items with no
        /// scope, then the whole run, this step, the last step, this split and the last split, each only if it has
        /// items. A group of items with no scope is one part with no title.
        public var sections: [Section] {
            var parts: [Section] = []
            let plain = items.filter { $0.scope == nil }
            if !plain.isEmpty { parts.append(Section(title: nil, items: plain)) }
            for scope in RunScope.allCases {
                let scoped = items.filter { $0.scope == scope }
                if !scoped.isEmpty { parts.append(Section(title: scope.suffix ?? "Whole Run", items: scoped)) }
            }
            return parts
        }
    }

    /// The statistics of a quantity over every scope that offers them, whole run first.
    static func measures(of quantity: RunQuantity) -> [RunScreenItem] {
        RunScope.allCases.flatMap { scope in
            RunStatistic.allCases.filter(scope.offers).map { RunScreenItem.measure(quantity, $0, scope) }
        }.filter { !shownByMetrics.contains($0) }
    }

    /// The whole-run statistics an older metric already shows, which the catalogue leaves out of the measures.
    static let shownByMetrics: Set<RunScreenItem> = [
        .measure(.heartRate, .current, .run), .measure(.heartRate, .average, .run), .measure(.heartRate, .maximum, .run),
        .measure(.pace, .current, .run), .measure(.pace, .average, .run),
    ]

    /// The scopes of a step or a split, which have a time, a distance and a climb of their own.
    static func spans(_ kind: RunSpanKind) -> [RunScreenItem] {
        [RunScope.step, .lastStep, .split, .lastSplit].map { RunScreenItem.span(kind, $0) }
    }

    /// The most items a group can have and still be listed in the picker's first level as rows of its own: a group
    /// that small would take a tap to open and show a row or two.
    public static let inlineLimit = 2

    /// The groups the picker's first level opens (those with more than ``inlineLimit`` items), in order.
    public static var browsableGroups: [Group] { groups.filter { $0.items.count > inlineLimit } }

    /// The items of the small groups, listed in the first level as they are.
    public static var inlineItems: [RunScreenItem] { groups.filter { $0.items.count <= inlineLimit }.flatMap(\.items) }

    /// Every group, in the order the picker shows them.
    public static let groups: [Group] = [
        Group(title: "Heart Rate", items: [
            .metric(.heartRate), .metric(.averageHeartRate), .metric(.maxHeartRate), .metric(.timeInZone), .metric(.timeSinceZoneEntry), .widget(.zoneBar), .widget(.zoneHistogram),
        ] + measures(of: .heartRate)),
        Group(title: "Cadence", items: measures(of: .cadence)),
        Group(title: "Speed", items: measures(of: .runningSpeed)),
        Group(title: "Power", items: measures(of: .runningPower)),
        Group(title: "Stride Length", items: measures(of: .strideLength)),
        Group(title: "Ground Contact Time", items: measures(of: .groundContactTime)),
        Group(title: "Vertical Oscillation", items: measures(of: .verticalOscillation)),
        Group(title: "Pace", items: [.metric(.currentPace), .metric(.averagePace)] + measures(of: .pace)),
        Group(title: "Distance and Time", items: [.metric(.distance), .metric(.totalTime)] + spans(.distance) + spans(.time)),
        Group(title: "Elevation and Grade", items: [.metric(.altitude), .metric(.elevationGain), .metric(.grade)] + spans(.climb)),
        Group(title: "Workout Step", items: [
            .widget(.stepCountdown), .widget(.targetBar), .metric(.stepTime), .metric(.stepDistance), .metric(.stepNumber), .widget(.paceBar), .metric(.timeRemaining), .metric(.finishTime),
        ]),
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
    /// The scope of a statistic or a span, or `nil` for the other items.
    var scope: RunScope? {
        switch self {
        case .measure(_, _, let scope), .span(_, let scope): scope
        case .metric, .widget: nil
        }
    }

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
            case .averageHeartRate: "Average Heart Rate"
            case .maxHeartRate: "Highest Heart Rate"
            case .altitude: "Altitude"
            case .elevationGain: "Elevation Gain"
            case .grade: "Grade"
            case .timeRemaining: "Time Left"
            case .finishTime: "Finish Time"
            case .stepNumber: "Step Number"
            case .stepTime: "Step Time"
            case .stepDistance: "Step Distance"
            case .timeInZone: "Time in This Zone, Total"
            case .timeSinceZoneEntry: "Time Since Entering Zone"
            }
        case .span(let kind, let scope): kind.title + ", " + (scope.suffix ?? "")
        case .measure(let quantity, let statistic, let scope):
            [statistic.prefix(for: quantity), quantity.title].compactMap { $0 }.joined(separator: " ") + (scope.suffix.map { ", " + $0 } ?? "")
        case .widget(let widget):
            switch widget {
            case .zoneBar: "Zone Bar"
            case .battery: "Battery and Forecast"
            case .stepCountdown: "Step Countdown"
            case .zoneHistogram: "Time in Zones"
            case .paceBar: "Pace Bar"
            case .targetBar: "Target Bar"
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
        case .metric(.averageHeartRate): "The mean heart rate of the run so far"
        case .metric(.maxHeartRate): "The highest heart rate of the run so far"
        case .metric(.altitude): "The altitude from the GPS"
        case .metric(.elevationGain): "How far the run has climbed"
        case .metric(.grade): "The slope of the last 50 metres or so, in percent"
        case .metric(.timeRemaining): "The time left in the workout, counting distances at the current pace; planned workouts only"
        case .metric(.finishTime): "The time of day the workout should end; planned workouts only"
        case .metric(.stepTime): "The time since the step began; planned workouts only"
        case .metric(.stepDistance): "The distance since the step began; planned workouts only"
        case .metric(.timeInZone): "All the time the run has spent in the zone the heart rate is in now, over the whole run"
        case .metric(.timeSinceZoneEntry): "How long the heart rate has been in its zone since it came in"
        case .widget(.zoneBar): "All the zones on one line with the heart rate and the step's target"
        case .widget(.battery): "The watch's charge and how much is left at the end"
        case .widget(.stepCountdown): "Time or distance left in the step; planned workouts only"
        case .widget(.zoneHistogram): "How long the run has spent in each zone"
        case .widget(.targetBar): "The bar for the step's target: the pace bar when the step has a pace target, the zone bar otherwise"
        case .widget(.paceBar): "The pace against the step's pace target; planned workouts only, and drawn only while the step has a pace target"
        case .metric(.stepNumber): "Which step it is, or which interval of a repeated block; planned workouts only"
        case .span(let kind, let scope): Self.spanDetail(kind, scope)
        case .measure(let quantity, let statistic, let scope): Self.measureDetail(quantity, statistic, scope)
        }
    }

    private static func spanDetail(_ kind: RunSpanKind, _ scope: RunScope) -> String {
        let what = switch kind {
        case .time: "The time"
        case .distance: "The distance"
        case .climb: "The metres climbed"
        }
        return switch scope {
        case .run: what
        case .step: what + " of the step being run; planned workouts only"
        case .lastStep: what + " of the step before this one; planned workouts only"
        case .split: what + " of the kilometre or mile being run"
        case .lastSplit: what + " of the kilometre or mile before this one"
        }
    }

    private static func measureDetail(_ quantity: RunQuantity, _ statistic: RunStatistic, _ scope: RunScope) -> String {
        let name = quantity.title.lowercased()
        let over: String = switch scope {
        case .run: "of the run so far"
        case .step: "of the step being run; planned workouts only"
        case .lastStep: "of the step before this one; planned workouts only"
        case .split: "of the kilometre or mile being run"
        case .lastSplit: "of the kilometre or mile before this one"
        }
        let isPace = quantity == .pace
        return switch statistic {
        case .current: "The latest \(name) the watch measured"
        case .average: "The mean \(name) \(over)"
        case .minimum: "The \(isPace ? "slowest" : "lowest") \(name) \(over)"
        case .maximum: "The \(isPace ? "fastest" : "highest") \(name) \(over)"
        case .median: "The median \(name) \(over)" + (scope == .run ? " (the last hour)" : "")
        }
    }

    /// The SF Symbol of the item.
    public var systemImage: String {
        switch self {
        case .metric(.totalTime): "clock"
        case .metric(.distance): "point.topleft.down.to.point.bottomright.curvepath"
        case .metric(.heartRate): "heart.fill"
        case .metric(.currentPace), .metric(.averagePace): "speedometer"
        case .metric(.averageHeartRate), .metric(.maxHeartRate): "heart"
        case .metric(.altitude), .metric(.elevationGain): "mountain.2"
        case .metric(.grade): "angle"
        case .metric(.timeRemaining): "hourglass"
        case .metric(.finishTime): "flag.checkered"
        case .metric(.stepTime): "stopwatch"
        case .metric(.stepDistance): "ruler"
        case .metric(.timeInZone): "heart.text.square"
        case .metric(.timeSinceZoneEntry): "timer"
        case .widget(.zoneBar): "chart.bar.xaxis"
        case .widget(.battery): "battery.75percent"
        case .widget(.stepCountdown): "timer"
        case .widget(.zoneHistogram): "chart.bar.fill"
        case .widget(.paceBar): "chart.bar.xaxis"
        case .widget(.targetBar): "target"
        case .metric(.stepNumber): "number"
        case .span(let kind, _):
            switch kind {
            case .time: "stopwatch"
            case .distance: "ruler"
            case .climb: "mountain.2"
            }
        case .measure(let quantity, _, _):
            switch quantity {
            case .pace: "speedometer"
            case .heartRate: "heart"
            case .cadence: "figure.run"
            case .runningSpeed: "gauge.with.needle"
            case .strideLength: "ruler"
            case .groundContactTime: "shoeprints.fill"
            case .verticalOscillation: "arrow.up.and.down"
            case .runningPower: "bolt.fill"
            }
        }
    }
}
