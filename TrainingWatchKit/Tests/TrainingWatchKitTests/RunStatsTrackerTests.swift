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

    @Test("a run under 10 km keeps all its points in the last-10-km profile, and standing still adds none")
    func recentProfileShortRun() throws {
        var stats = RunStatsTracker()
        for meter in stride(from: 0.0, through: 1000, by: RunStatsTracker.recentSpacing) { stats.add(altitude: 20, atDistance: meter) }
        #expect(stats.recentProfile.first?.meters == 0)
        #expect(stats.recentProfile.count == 41)
        for _ in 0..<200 { stats.add(altitude: 20, atDistance: 1000) }
        #expect(stats.recentProfile.count == 41)
    }

    @Test("one fix that is far off doesn't spike the profiles, and a real climb still shows")
    func profileSmoothing() throws {
        var stats = RunStatsTracker()
        for (index, meter) in stride(from: 0.0, through: 200, by: 10).enumerated() {
            // A flat 30 m with one bad fix of 90 m.
            stats.add(altitude: index == 10 ? 90 : 30, atDistance: meter)
        }
        #expect(stats.profile.map(\.altitude).max() == 30)
        #expect(stats.recentProfile.map(\.altitude).max() == 30)
        var climb = RunStatsTracker()
        for (index, meter) in stride(from: 0.0, through: 200, by: 10).enumerated() { climb.add(altitude: 30 + Double(index), atDistance: meter) }
        let last = try #require(climb.profile.last)
        #expect(last.altitude >= 48)
    }

    @Test("standing still adds no profile points")
    func profileStationary() {
        var stats = RunStatsTracker()
        stats.add(altitude: 100, atDistance: 0)
        for _ in 0..<500 { stats.add(altitude: 101, atDistance: 1) }
        #expect(stats.profile.count == 1)
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
