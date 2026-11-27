import Foundation

/// How the profile's distance and altitude map onto the drawing (WATCH-149): shared by the line and the grid, so a
/// grid line sits exactly where the altitude or distance it names is drawn.
struct ElevationScale {
    /// The room kept above the highest and below the lowest point, as a share of the height.
    static let margin = 0.12
    /// The least altitude range (metres) the height stands for, so a flat stretch with GPS noise isn't blown up to
    /// look like a climb.
    static let minimumRange = 10.0

    let startMeters: Double
    let length: Double
    /// The altitude at the bottom of the drawn range (above the bottom margin) and the metres the range spans.
    let baseAltitude: Double
    let range: Double

    /// `nil` for fewer than two points: there is nothing to scale.
    init?(_ points: [ElevationPoint]) {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        startMeters = first.meters
        length = max(last.meters - first.meters, 1)
        let low = points.map(\.altitude).min() ?? 0
        let high = points.map(\.altitude).max() ?? 0
        range = max(high - low, Self.minimumRange)
        // A range wider than the climb is centred on it.
        baseAltitude = low - (range - (high - low)) / 2
    }

    /// The place along the width of a distance: 0 at the first point, 1 at the last.
    func x(meters: Double) -> Double { (meters - startMeters) / length }

    /// The height of an altitude: 0 at the bottom, 1 at the top, with the margins kept.
    func y(altitude: Double) -> Double {
        Self.margin + (1 - 2 * Self.margin) * (altitude - baseAltitude) / range
    }
}
