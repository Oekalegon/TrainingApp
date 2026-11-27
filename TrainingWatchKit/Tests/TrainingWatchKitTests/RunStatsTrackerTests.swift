import Testing
import TrainingCore
@testable import TrainingWatchKit

@Suite("RunStatsTracker (WATCH-135)")
struct RunStatsTrackerTests {
    @Test("average and highest heart rate")
    func heartRate() {
        var stats = RunStatsTracker()
        #expect(stats.averageHeartRate == nil)
        for bpm in [120.0, 140, 160] { stats.add(heartRate: bpm) }
        #expect(stats.averageHeartRate == 140)
        #expect(stats.maxHeartRate == 160)
    }

    @Test("a climb counts only past the threshold, noise doesn't")
    func climb() {
        var stats = RunStatsTracker()
        for (i, altitude) in [100.0, 101, 99.5, 100.5, 104, 108, 105, 111].enumerated() {
            stats.add(altitude: altitude, atDistance: Double(i) * 10)
        }
        // 100 -> 104 (+4), 104 -> 108 (+4), a drop of 3 resets the reference to 105, then +6.
        #expect(stats.elevationGain == 14)
        #expect(stats.altitude == 111)
    }

    @Test("grade is the slope over at least the window, and nil before it")
    func grade() {
        var stats = RunStatsTracker()
        stats.add(altitude: 100, atDistance: 0)
        stats.add(altitude: 101, atDistance: 20)
        #expect(stats.grade == nil)
        stats.add(altitude: 105, atDistance: 60)
        let grade = try! #require(stats.grade)
        #expect(abs(grade - 8.333) < 0.01)
    }

    @Test("standing still doesn't pile up points, and the grade stays right after")
    func stationary() {
        var stats = RunStatsTracker()
        stats.add(altitude: 100, atDistance: 0)
        stats.add(altitude: 105, atDistance: 60)
        for _ in 0..<1000 { stats.add(altitude: 105, atDistance: 60) }
        let grade = try! #require(stats.grade)
        #expect(abs(grade - 8.333) < 0.01)
    }

    @Test("the elevation profile (WATCH-149) keeps the start and the latest point and never grows past its limit")
    func profile() throws {
        var stats = RunStatsTracker()
        for meter in stride(from: 0.0, through: 20_000, by: 10) { stats.add(altitude: 50 + meter / 100, atDistance: meter) }
        #expect(stats.profile.count <= RunStatsTracker.maximumProfilePoints)
        #expect(stats.profile.count > RunStatsTracker.maximumProfilePoints / 4)
        #expect(stats.profile.first == ElevationPoint(meters: 0, altitude: 50))
        // The run is covered to its end, within one thinned spacing.
        let last = try #require(stats.profile.last)
        #expect(last.meters > 19_000)
        #expect(stats.profile.map(\.meters) == stats.profile.map(\.meters).sorted())
    }

    @Test("the last-10-km profile keeps fine points, drops what is further back and stays bounded")
    func recentProfile() throws {
        var stats = RunStatsTracker()
        for meter in stride(from: 0.0, through: 30_000, by: 10) { stats.add(altitude: 50 + meter / 100, atDistance: meter) }
        let recent = stats.recentProfile
        #expect(recent.count <= Int(RunStatsTracker.recentWindowMeters / RunStatsTracker.recentSpacing) + 1)
        let first = try #require(recent.first)
        let last = try #require(recent.last)
        #expect(last.meters == 30_000)
        #expect(last.meters - first.meters <= RunStatsTracker.recentWindowMeters)
        #expect(last.meters - first.meters > RunStatsTracker.recentWindowMeters - 2 * RunStatsTracker.recentSpacing)
        // Finer than the whole-run profile, which is thinned to a few hundred metres a point by now.
        #expect(recent.count > stats.profile.count)
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
        #expect(ElevationGrade.gradient(for: points).count == points.count)
    }

    @Test("standing still adds no profile points")
    func profileStationary() {
        var stats = RunStatsTracker()
        stats.add(altitude: 100, atDistance: 0)
        for _ in 0..<500 { stats.add(altitude: 101, atDistance: 1) }
        #expect(stats.profile.count == 1)
    }

    @Test("the profile is scaled to fit, with room above and below, and a flat run stays in the middle")
    func profileShape() {
        let climb = ElevationProfileShape.normalized([
            ElevationPoint(meters: 0, altitude: 100), ElevationPoint(meters: 500, altitude: 150), ElevationPoint(meters: 1000, altitude: 200),
        ])
        #expect(climb.map(\.x) == [0, 0.5, 1])
        #expect(abs(climb[0].y - ElevationProfileShape.margin) < 1e-9)
        #expect(abs(climb[2].y - (1 - ElevationProfileShape.margin)) < 1e-9)
        // Under the least range, a flat run is a line in the middle and not stretched into a climb.
        let flat = ElevationProfileShape.normalized([ElevationPoint(meters: 0, altitude: 80), ElevationPoint(meters: 100, altitude: 80.5)])
        #expect(flat.allSatisfy { abs($0.y - 0.5) < 0.05 })
        #expect(ElevationProfileShape.normalized([ElevationPoint(meters: 0, altitude: 80)]).isEmpty)
        #expect(RunWidget.elevationProfile.height == 2)
        #expect(!RunWidget.elevationProfile.requiresSteps)
    }

    @Test("metrics that need steps are marked")
    func steps() {
        #expect(RunScreenItem.metric(.timeRemaining).requiresSteps)
        #expect(RunScreenItem.metric(.finishTime).requiresSteps)
        #expect(RunScreenItem.metric(.stepTime).requiresSteps)
        #expect(!RunScreenItem.metric(.timeInZone).requiresSteps)
        #expect(!RunScreenItem.metric(.timeSinceZoneEntry).requiresSteps)
        #expect(!RunScreenItem.metric(.altitude).requiresSteps)
        #expect(RunMetric.standard.count == 5)
    }
}
