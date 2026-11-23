import Foundation
import Testing
@testable import TrainingWatchKit

@Suite("BatteryWarning (WATCH-110)")
struct BatteryWarningTests {
    private func battery(_ level: Float, charging: Bool = false) -> BatteryDisplay {
        BatteryDisplay(level: level, isCharging: charging)
    }

    private func projection(level: Float, seconds: TimeInterval) -> BatteryProjection? {
        BatteryProjection(
            battery: battery(level), readings: [], remaining: RemainingEstimate(seconds: seconds, isComplete: true))
    }

    @Test("no warning above 20% with a forecast that is enough")
    func quiet() {
        var tracker = BatteryWarningTracker()
        #expect(tracker.update(battery: battery(0.8), projection: projection(level: 0.8, seconds: 3600), at: 0) == nil)
        #expect(tracker.update(battery: battery(0.5), projection: nil, at: 10) == nil)
    }

    @Test("the charge alone warns in a free run: 20% or less is yellow, 10% orange, under 5% red")
    func charge() throws {
        var tracker = BatteryWarningTracker()
        let first = tracker.update(battery: battery(0.2), projection: nil, at: 0)
        #expect(first?.level == .tight)
        #expect(tracker.update(battery: battery(0.19), projection: nil, at: 5) == nil)
        let second = tracker.update(battery: battery(0.1), projection: nil, at: 10)
        #expect(second?.level == .critical)
        let redOptional = tracker.update(battery: battery(0.04), projection: nil, at: 15)
        let red = try #require(redOptional)
        #expect(red.level == .runsOut)
        #expect(red.title == "BATTERY NEARLY EMPTY")
        #expect(red.detail == "4% LEFT")
    }

    @Test("the forecast warns before the charge is low")
    func forecast() throws {
        var tracker = BatteryWarningTracker()
        // 50% now and 5 hours to go at the typical 12% an hour: it runs out.
        let projection = projection(level: 0.5, seconds: 5 * 3600)
        let warningOptional = tracker.update(battery: battery(0.5), projection: projection, at: 0)
        let warning = try #require(warningOptional)
        #expect(warning.level == .runsOut)
        #expect(warning.title == "BATTERY WON'T LAST")
        #expect(warning.detail.hasPrefix("50%  ·  EMPTY IN 4:10"))
        #expect(warning.spoken.contains("battery won't last"))
    }

    @Test("each level is given once, and a worse one warns again")
    func once() throws {
        var tracker = BatteryWarningTracker()
        // 30% with 1 hour 30 minutes to go: 12% at the end, critical after the margin.
        let critical = projection(level: 0.3, seconds: 5400)
        let first = tracker.update(battery: battery(0.3), projection: critical, at: 0)
        #expect(first?.level == .critical)
        #expect(tracker.update(battery: battery(0.3), projection: critical, at: 5) == nil)
        #expect(tracker.update(battery: battery(0.29), projection: critical, at: 10) == nil)
        // It gets worse: runs out.
        let worse = projection(level: 0.2, seconds: 3 * 3600)
        let second = tracker.update(battery: battery(0.2), projection: worse, at: 20)
        #expect(second?.level == .runsOut)
    }

    @Test("a level that wavers is not warned about again, unless it stayed lower for two minutes")
    func waver() throws {
        var tracker = BatteryWarningTracker()
        // Critical, then yellow for a minute, then critical again: no new warning.
        let critical = projection(level: 0.3, seconds: 5400)
        let tight = projection(level: 0.3, seconds: 3600)
        #expect(tracker.update(battery: battery(0.3), projection: critical, at: 0) != nil)
        #expect(tracker.update(battery: battery(0.3), projection: tight, at: 10) == nil)
        #expect(tracker.update(battery: battery(0.3), projection: tight, at: 70) == nil)
        #expect(tracker.update(battery: battery(0.3), projection: critical, at: 80) == nil)
        // Lower for two minutes (here: fine again), and then critical: a new warning.
        let fine = projection(level: 0.9, seconds: 600)
        #expect(tracker.update(battery: battery(0.9), projection: fine, at: 100) == nil)
        #expect(tracker.update(battery: battery(0.9), projection: fine, at: 230) == nil)
        #expect(tracker.update(battery: battery(0.3), projection: critical, at: 240) != nil)
    }

    @Test("a charging battery gives no warning, and a plain level gives none either")
    func charging() {
        var tracker = BatteryWarningTracker()
        #expect(tracker.update(battery: battery(0.05, charging: true), projection: nil, at: 0) == nil)
        #expect(tracker.update(battery: battery(-1), projection: nil, at: 5) == nil)
    }

    @Test("the colours are the battery bar's, with text that can be read on them")
    func colors() {
        let make = { (level: BatteryWarning.Level) in
            BatteryWarning(level: level, title: "", detail: "", spoken: "")
        }
        #expect(make(.tight).color == .yellow && make(.tight).textColor == .black)
        #expect(make(.critical).color == .orange && make(.critical).textColor == .black)
        #expect(make(.runsOut).color == .red && make(.runsOut).textColor == .white)
        #expect(BatteryWarning.Level.tight < .critical && BatteryWarning.Level.critical < .runsOut)
    }
}

@Suite("LaunchArgument (WATCH-110)")
struct LaunchArgumentTests {
    @Test("a number comes out of a number, and out of the text a launch argument gives")
    func numbers() {
        #expect(LaunchArgument.double(from: 0.25) == 0.25)
        #expect(LaunchArgument.double(from: NSNumber(value: 2.6)) == 2.6)
        #expect(LaunchArgument.double(from: "0.25") == 0.25)
        #expect(LaunchArgument.double(from: " 3 ") == 3)
        #expect(LaunchArgument.double(from: "fast") == nil)
        #expect(LaunchArgument.double(from: nil) == nil)
    }
}
