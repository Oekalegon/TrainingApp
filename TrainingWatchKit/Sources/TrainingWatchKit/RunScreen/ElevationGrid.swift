import Foundation

/// The horizontal (altitude) and vertical (distance) lines drawn behind the profile, at round values (WATCH-149).
enum ElevationGrid {
    /// At most about this many lines either way, so the labels have room on a watch's width.
    static let altitudeLines = 3.0
    static let distanceLines = 3.0
    /// The room a label such as "10.5 km" needs at 9 points.
    static let textRoom = 34.0

    /// The smallest 1, 2 or 5 times a power of ten that is at least `value`.
    static func niceStep(atLeast value: Double) -> Double {
        guard value > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(value)))
        return [1.0, 2, 5, 10].map { $0 * magnitude }.first { $0 >= value * (1 - 1e-9) } ?? 10 * magnitude
    }

    /// The altitudes (metres) of the horizontal lines: multiples of a round step inside the drawn range.
    static func altitudes(_ scale: ElevationScale) -> [Double] {
        multiples(of: niceStep(atLeast: scale.range / altitudeLines), from: scale.baseAltitude, to: scale.baseAltitude + scale.range)
    }

    /// The distances (metres, from the start of the run) of the vertical lines: multiples of a round step inside the graph.
    static func distances(_ scale: ElevationScale) -> [Double] {
        multiples(of: niceStep(atLeast: scale.length / distanceLines), from: scale.startMeters, to: scale.startMeters + scale.length)
    }

    /// The multiples of `step` strictly between `low` and `high`, so none sits on the edge of the drawing.
    private static func multiples(of step: Double, from low: Double, to high: Double) -> [Double] {
        var result: [Double] = []
        var value = (low / step).rounded(.down) * step + step
        while value < high - step * 0.01 {
            result.append(value)
            value += step
        }
        return result
    }

    static func altitudeLabel(_ meters: Double) -> String { "\(Int(meters.rounded())) m" }

    /// "2 km", "0.5 km", or "0.05 km" early in a run: up to two decimals, without trailing zeros.
    static func distanceLabel(_ meters: Double) -> String {
        var text = String(format: "%.2f", meters / 1000)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + " km"
    }

    /// Whether a distance label fits to the right of its line, which is at `x` in a drawing `width` wide. Near the
    /// right edge it would be cut off, so it goes to the left of the line instead.
    static func labelFitsRight(lineAt x: Double, width: Double) -> Bool { x + 2 + textRoom <= width }
}
