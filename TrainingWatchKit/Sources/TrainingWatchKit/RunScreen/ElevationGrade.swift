import SwiftUI

/// How steep the ground is along the elevation profile, and the colour that says so (WATCH-149).
enum ElevationGrade {
    /// The grade at a point is taken between the points at least this many metres before and after it, so GPS noise
    /// between close points isn't drawn as a steep stretch.
    static let window = 50.0
    /// The grade (percent, up or down) at which the line is fully red.
    static let redGrade = 25.0

    /// The grade in percent at each point (positive uphill).
    static func grades(of points: [ElevationPoint]) -> [Double] {
        points.indices.map { index in
            let here = points[index].meters
            var low = index
            while low > 0, here - points[low].meters < window { low -= 1 }
            var high = index
            while high < points.count - 1, points[high].meters - here < window { high += 1 }
            let run = points[high].meters - points[low].meters
            return run > 0 ? (points[high].altitude - points[low].altitude) / run * 100 : 0
        }
    }

    /// The hue (0 red … 1/3 green) for a grade: green on the flat, through yellow and orange, to red at ``redGrade``
    /// and steeper, whichever way the ground slopes.
    static func hue(forGrade grade: Double) -> Double {
        (1.0 / 3) * (1 - min(abs(grade) / redGrade, 1))
    }

    static func color(forGrade grade: Double) -> Color {
        Color(hue: hue(forGrade: grade), saturation: 0.85, brightness: 0.95)
    }

    /// The stops of a left-to-right gradient that gives each point its grade's colour at its place along the width.
    static func stops(positions: [Double], grades: [Double]) -> [Gradient.Stop] {
        zip(positions, grades).map { Gradient.Stop(color: color(forGrade: $1), location: $0) }
    }
}
