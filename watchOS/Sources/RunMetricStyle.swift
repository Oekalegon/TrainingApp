import SwiftUI

extension View {
    /// The simulator can't put the wrist down: with `-fakeDimmed` the view and what is in it see
    /// `isLuminanceReduced` as true (WATCH-125, WATCH-129). Does nothing on a real watch. The run's pages
    /// need it on themselves too, since the pager hands them the system's own value.
    @ViewBuilder
    func fakeDimmable() -> some View {
        #if targetEnvironment(simulator)
        if CommandLine.arguments.contains("-fakeDimmed") {
            environment(\.isLuminanceReduced, true)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// The fonts and spacing of a value with its unit ("169 BPM", "ZONE 4.4"), shared by the standard
/// metrics screen and the zone dial's heart-rate row so they look alike.
enum RunMetricStyle {
    /// The size of a value, in points.
    static let valueSize = 30.0
    /// The gap between two rows of metrics, on top of the values' trimmed line height. Meant to leave room for
    /// six rows on an Ultra and five on the other watches (worked out from the screen heights, not checked on them).
    static let rowSpacing = 3.0
    /// How bright the run screens stay with the wrist down (WATCH-125; a guess to check on a watch).
    static let dimmedOpacity = 0.65
    /// The gap between a value and its unit or word.
    static let unitSpacing = 3.0

    static var valueFont: Font {
        .system(size: valueSize, weight: .medium, design: .rounded).monospacedDigit()
    }

    /// The small capitals beside a value: "KM", "BPM", "ZONE".
    static var unitFont: Font {
        .system(size: 17, weight: .semibold, design: .rounded)
    }

    /// The two small lines beside a value, such as "AVERAGE" over "PACE": together no taller than the value.
    static var captionFont: Font {
        .system(size: 12, weight: .semibold, design: .rounded)
    }

    /// A caption of two lines, such as "REMAINING" over "TIME".
    /// - Parameter shrinks: Whether the caption may shrink to fit; off where it must stay the size of the
    ///   other captions ("REP" beside it).
    static func caption(_ top: String, _ bottom: String, shrinks: Bool = true) -> some View {
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
