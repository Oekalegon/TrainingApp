import SwiftUI
import Testing
@testable import TrainingWatchKit

@Suite("Elevation profile (WATCH-149)")
struct ElevationProfileTests {
    /// A steady climb: 4 km, 12 m up to 52 m.
    private let climb = (0...40).map { ElevationPoint(meters: Double($0) * 100, altitude: 12 + Double($0)) }

    @Test("the scale puts the first point at the left and the last at the right, with room above and below")
    func scale() throws {
        let points = [
            ElevationPoint(meters: 0, altitude: 100), ElevationPoint(meters: 500, altitude: 150), ElevationPoint(meters: 1000, altitude: 200),
        ]
        let layout = try #require(ElevationProfileLayout(points))
        #expect(layout.normalized.map(\.x) == [0, 0.5, 1])
        #expect(abs(layout.normalized[0].y - ElevationScale.margin) < 1e-9)
        #expect(abs(layout.normalized[2].y - (1 - ElevationScale.margin)) < 1e-9)
        #expect(layout.grades.count == 3 && layout.stops.count == 3)
        // Under the least range, a flat run is a line in the middle and not stretched into a climb.
        let flat = try #require(ElevationProfileLayout([ElevationPoint(meters: 0, altitude: 80), ElevationPoint(meters: 100, altitude: 80.5)]))
        #expect(flat.normalized.allSatisfy { abs($0.y - 0.5) < 0.05 })
        #expect(ElevationProfileLayout([ElevationPoint(meters: 0, altitude: 80)]) == nil)
        #expect(ElevationScale([]) == nil)
        #expect(RunWidget.elevationProfile.height == 2 && RunWidget.elevationRecent.height == 2)
        #expect(!RunWidget.elevationProfile.requiresSteps && !RunWidget.elevationRecent.requiresSteps)
    }

    @Test("the shape draws the line from the first point, or the area down to the bottom edge")
    func shape() {
        let points = [CGPoint(x: 0, y: 0.2), CGPoint(x: 0.5, y: 0.8), CGPoint(x: 1, y: 0.4)]
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        let line = ElevationProfileShape(normalized: points, closed: false).path(in: rect)
        #expect(line.currentPoint == CGPoint(x: 100, y: 30))
        #expect(line.boundingRect.minY == 10 && line.boundingRect.maxY == 40)
        let area = ElevationProfileShape(normalized: points, closed: true).path(in: rect)
        #expect(area.boundingRect.maxY == 50 && area.boundingRect.minX == 0 && area.boundingRect.maxX == 100)
        #expect(ElevationProfileShape(normalized: [CGPoint(x: 0, y: 0.5)], closed: true).path(in: rect).isEmpty)
    }

    @Test("grade colours go from green on the flat to red at 25 % and steeper, up or down")
    func gradeColour() {
        #expect(abs(ElevationGrade.hue(forGrade: 0) - 1.0 / 3) < 1e-9)
        #expect(ElevationGrade.hue(forGrade: 25) == 0)
        #expect(ElevationGrade.hue(forGrade: 40) == 0)
        #expect(ElevationGrade.hue(forGrade: -25) == 0)
        #expect(abs(ElevationGrade.hue(forGrade: 12.5) - 1.0 / 6) < 1e-9)
    }

    @Test("the grade at a point is taken over a stretch, so close noisy points don't read as steep")
    func gradeStretch() {
        // A steady 10 % climb with 1 m of noise on points 10 m apart.
        let points = (0..<30).map { ElevationPoint(meters: Double($0) * 10, altitude: Double($0) + ($0 % 2 == 0 ? 0.5 : -0.5)) }
        let grades = ElevationGrade.grades(of: points)
        #expect(grades.count == points.count)
        #expect(grades[15...20].allSatisfy { abs($0 - 10) < 2 })
    }

    @Test("the grade at the ends uses the stretch that exists, and the same distance twice gives a level grade")
    func gradeEnds() {
        let grades = ElevationGrade.grades(of: climb)
        #expect(grades.allSatisfy { abs($0 - 1) < 1e-9 })
        // Two points at the same distance: no run, no grade, and no division by zero.
        let same = ElevationGrade.grades(of: [ElevationPoint(meters: 50, altitude: 10), ElevationPoint(meters: 50, altitude: 30)])
        #expect(same == [0, 0])
        #expect(ElevationGrade.grades(of: []).isEmpty)
    }

    @Test("the grid draws lines at round altitudes and distances inside the graph, with labels")
    func grid() throws {
        #expect(ElevationGrid.niceStep(atLeast: 1750) == 2000)
        #expect(ElevationGrid.niceStep(atLeast: 3.3) == 5)
        #expect(ElevationGrid.niceStep(atLeast: 10) == 10)
        #expect(ElevationGrid.niceStep(atLeast: 0.04) == 0.05)
        let scale = try #require(ElevationScale(climb))
        // 4 km: a line every 2 km, none on the edges.
        #expect(ElevationGrid.distances(scale) == [2000])
        let altitudes = ElevationGrid.altitudes(scale)
        #expect(!altitudes.isEmpty && altitudes.count <= 4)
        // Each altitude line is inside the drawn range, and sits where the line draws that altitude.
        for altitude in altitudes {
            #expect(altitude > scale.baseAltitude && altitude < scale.baseAltitude + scale.range)
            #expect(scale.y(altitude: altitude) > 0 && scale.y(altitude: altitude) < 1)
        }
        #expect(ElevationGrid.distanceLabel(2000) == "2 km")
        #expect(ElevationGrid.distanceLabel(500) == "0.5 km")
        #expect(ElevationGrid.distanceLabel(50) == "0.05 km")
        #expect(ElevationGrid.distanceLabel(12_000) == "12 km")
        #expect(ElevationGrid.altitudeLabel(49.6) == "50 m")
    }

    @Test("a distance label that would run past the right edge goes to the left of its line")
    func labelPlacement() {
        #expect(ElevationGrid.labelFitsRight(lineAt: 100, width: 190))
        #expect(!ElevationGrid.labelFitsRight(lineAt: 170, width: 190))
        #expect(ElevationGrid.labelFitsRight(lineAt: 190 - 2 - ElevationGrid.textRoom, width: 190))
    }

    @Test("VoiceOver says the change, the altitude now, the grade now and the steepest stretch")
    func spoken() {
        let climbing = ElevationProfileSummary.spoken(climb, grades: ElevationGrade.grades(of: climb))
        #expect(climbing == "40 metres higher than the start of the graph, now 52 metres, 1 percent uphill now".replacingOccurrences(of: "1 percent uphill now", with: "level now"))
        // A hill up and down: 10 % up, then 20 % down to a level finish.
        var points = (0...10).map { ElevationPoint(meters: Double($0) * 100, altitude: Double($0) * 10) }
        points += (11...15).map { ElevationPoint(meters: Double($0) * 100, altitude: 100 - Double($0 - 10) * 20) }
        points += (16...20).map { ElevationPoint(meters: Double($0) * 100, altitude: 0) }
        let text = ElevationProfileSummary.spoken(points, grades: ElevationGrade.grades(of: points))
        #expect(text.hasPrefix("no change in altitude, now 0 metres, level now, steepest stretch 20 percent downhill"))
        #expect(ElevationProfileSummary.spoken([], grades: []) == "no altitude yet")
        #expect(ElevationProfileSummary.spoken([ElevationPoint(meters: 0, altitude: 5)], grades: [0]) == "no altitude yet")
    }
}
