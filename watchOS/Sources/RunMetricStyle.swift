import SwiftUI

/// The fonts and spacing of a value with its unit ("169 BPM", "ZONE 4.4"), shared by the standard
/// metrics screen and the zone dial's heart-rate row so they look alike.
enum RunMetricStyle {
    /// The size of a value, in points.
    static let valueSize = 30.0
    /// The gap between a value and its unit or word.
    static let unitSpacing = 3.0

    static var valueFont: Font {
        .system(size: valueSize, weight: .medium, design: .rounded).monospacedDigit()
    }

    /// The small capitals beside a value: "KM", "BPM", "ZONE".
    static var unitFont: Font {
        .system(size: 17, weight: .semibold, design: .rounded)
    }
}
