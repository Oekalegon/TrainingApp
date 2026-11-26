import Testing
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

    @Test("metrics that need steps are marked")
    func steps() {
        #expect(RunScreenItem.metric(.timeRemaining).requiresSteps)
        #expect(RunScreenItem.metric(.finishTime).requiresSteps)
        #expect(!RunScreenItem.metric(.altitude).requiresSteps)
        #expect(RunMetric.standard.count == 5)
    }
}
