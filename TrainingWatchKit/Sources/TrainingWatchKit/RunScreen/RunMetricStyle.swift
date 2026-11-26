import SwiftUI

/// How often a run screen redraws (WATCH-125): every second, or with the wrist down on the minute
/// (not a minute from when the wrist went down, so the time shown is never nearly a minute behind).
public struct RunScreenSchedule: TimelineSchedule {
    public let dimmed: Bool

    public init(dimmed: Bool) { self.dimmed = dimmed }

    public func entries(from start: Date, mode: Mode) -> AnySequence<Date> {
        let calendar = Calendar.current
        let step: (Date) -> Date? = { date in
            if dimmed {
                // The start of the next minute.
                calendar.nextDate(after: date, matching: DateComponents(second: 0), matchingPolicy: .nextTime)
            } else {
                date.addingTimeInterval(1)
            }
        }
        return AnySequence(sequence(first: start, next: step))
    }
}

extension TimelineSchedule where Self == RunScreenSchedule {
    public static func runScreen(dimmed: Bool) -> RunScreenSchedule { RunScreenSchedule(dimmed: dimmed) }
}


/// The fonts and spacing of a value with its unit ("169 BPM", "ZONE 4.4"), shared by the standard
/// screens' metric rows so they look alike.
public enum RunMetricStyle {
    /// The size of a value, in points.
    public static let valueSize = 30.0
    /// The gap between two rows of metrics, on top of the values' trimmed line height. Meant to leave room for
    /// six rows on an Ultra and five on the other watches (worked out from the screen heights, not checked on them).
    public static let rowSpacing = 3.0
    /// How bright the run screens stay with the wrist down (WATCH-125; a guess to check on a watch).
    public static let dimmedOpacity = 0.65
    /// The gap between a value and its unit or word.
    public static let unitSpacing = 3.0

    public static var valueFont: Font {
        .system(size: valueSize, weight: .medium, design: .rounded).monospacedDigit()
    }

    /// The small capitals beside a value: "KM", "BPM", "ZONE".
    public static var unitFont: Font {
        .system(size: 17, weight: .semibold, design: .rounded)
    }

    /// The two small lines beside a value, such as "AVERAGE" over "PACE": together no taller than the value.
    public static var captionFont: Font {
        .system(size: 12, weight: .semibold, design: .rounded)
    }

    /// A caption of two lines, such as "REMAINING" over "TIME".
    /// - Parameter shrinks: Whether the caption may shrink to fit; off where it must stay the size of the
    ///   other captions ("REP" beside it).
    public static func caption(_ top: String, _ bottom: String, shrinks: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(top)
            Text(bottom)
        }
        .font(captionFont)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(shrinks ? 0.7 : 1)
        // A caption that may not shrink isn't cut either: whatever is beside it gives way.
        .fixedSize(horizontal: !shrinks, vertical: false)
    }
}

extension StepHeartRateTarget.Status {
    /// The colour of the heart rate and its zone against the step's target: blue under it, red over it,
    /// white in it (and without a target), so a glance says whether to speed up or slow down.
    public static func displayColor(_ status: StepHeartRateTarget.Status?) -> Color {
        switch status {
        case .below: Color(red: 0.35, green: 0.65, blue: 1.0)
        case .above: Color(red: 1.0, green: 0.4, blue: 0.4)
        case .inside, nil: .white
        }
    }
}

extension StepPaceTarget.Position {
    /// The same verdict as a heart rate's, so one colour rule serves both bars: slower than the target is "below".
    public var asStatus: StepHeartRateTarget.Status {
        switch self {
        case .tooSlow: .below
        case .tooFast: .above
        case .inside: .inside
        }
    }
}
