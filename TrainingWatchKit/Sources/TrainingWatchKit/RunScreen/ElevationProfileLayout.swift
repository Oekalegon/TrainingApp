import SwiftUI

/// Everything the elevation profile's parts draw from, worked out once per body (WATCH-149): the line, the fade, the
/// position dot and the grid all share it, so a run screen that redraws every second doesn't scale the same points
/// four times.
struct ElevationProfileLayout {
    let scale: ElevationScale
    /// Each point as a fraction of the width (0 at the first point, 1 at the last) and the height (0 at the bottom).
    let normalized: [CGPoint]
    /// The grade in percent at each point.
    let grades: [Double]
    /// The line's colours: each point's grade colour at its place along the width.
    let stops: [Gradient.Stop]

    /// `nil` for fewer than two points.
    init?(_ points: [ElevationPoint]) {
        guard let scale = ElevationScale(points) else { return nil }
        let normalized = points.map { CGPoint(x: scale.x(meters: $0.meters), y: scale.y(altitude: $0.altitude)) }
        let grades = ElevationGrade.grades(of: points)
        self.scale = scale
        self.normalized = normalized
        self.grades = grades
        self.stops = ElevationGrade.stops(positions: normalized.map { Double($0.x) }, grades: grades)
    }
}
