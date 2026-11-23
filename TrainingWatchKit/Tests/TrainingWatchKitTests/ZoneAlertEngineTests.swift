import Foundation
import Testing
import TrainingCore
@testable import TrainingWatchKit

@Suite("ZoneAlertEngine (WATCH-106)")
struct ZoneAlertEngineTests {
    private let bands = ZoneBands(zones: WatchZones(settings: .init(
        effectiveDate: .distantPast, restingHeartRateBPM: 55, maxHeartRateBPM: 190)))!

    /// A heart-rate zone's bpm range: zone 3 is 149.5 to 163 (13.5 wide), zone 4 163 to 176.5.
    private func target(_ zone: Int) throws -> ClosedRange<Double> {
        let step = WorkoutStep(kind: .work, goal: .time(60), target: .heartRateZone(zone))
        return try #require(StepHeartRateTarget(step: step, bands: bands)).bpm
    }

    /// Feeds one reading per second from `from` to `to` (seconds), all at `value`, and collects the alerts.
    private func feed(
        _ engine: inout ZoneAlertEngine, _ value: Double, from: Int, to: Int
    ) -> [(Int, ZoneAlert)] {
        (from...to).compactMap { t in engine.add(value, at: Double(t)).map { (t, $0) } }
    }

    @Test("a step announces itself")
    func stepStart() throws {
        var engine = ZoneAlertEngine()
        #expect(engine.beginStep(target: try target(3), at: 0) == .stepStarted)
    }

    @Test("no target, no alerts")
    func noTarget() {
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: nil, at: 0)
        #expect(feed(&engine, 60, from: 1, to: 60).isEmpty)
    }

    @Test("inside the zone is quiet, and so is just outside it, within the hysteresis")
    func quiet() throws {
        let zone = try target(3)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        #expect(feed(&engine, zone.lowerBound + 2, from: 1, to: 60).isEmpty)
        // 10% of a 13.5 bpm zone is 1.35 bpm.
        #expect(feed(&engine, zone.lowerBound - 1, from: 61, to: 120).isEmpty)
    }

    @Test("the hysteresis is a tenth of the zone's width, at least 1 bpm")
    func hysteresisScalesWithWidth() {
        var narrow = ZoneAlertEngine()
        _ = narrow.beginStep(target: 150...152, at: 0)
        // 2 bpm wide: the floor of 1 bpm applies, so 2 bpm under is out.
        #expect(!feed(&narrow, 148, from: 1, to: 15).isEmpty)
        var wide = ZoneAlertEngine()
        _ = wide.beginStep(target: 150...200, at: 0)
        // 50 bpm wide: 5 bpm of margin, so 4 bpm under is still quiet.
        #expect(feed(&wide, 146, from: 1, to: 15).isEmpty)
    }

    @Test("under the zone: too low after the 2 s start grace, then repeated, and back in zone once")
    func tooLowThenBack() throws {
        let zone = try target(3)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        let alerts = feed(&engine, zone.lowerBound - 5, from: 1, to: 50)
        #expect(alerts.map(\.1) == [.tooLow, .tooLow, .tooLow])
        #expect(alerts.first!.0 == 2)
        #expect(alerts[1].0 - alerts[0].0 == 20)
        let back = feed(&engine, zone.lowerBound + 3, from: 51, to: 80)
        #expect(back.map(\.1) == [.backInZone])
    }

    @Test("over the zone is too high")
    func tooHigh() throws {
        let zone = try target(3)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        #expect(feed(&engine, zone.upperBound + 5, from: 1, to: 15).map(\.1) == [.tooHigh])
    }

    @Test("well outside the zone is the far alert, above and below")
    func far() throws {
        let zone = try target(3)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        #expect(feed(&engine, zone.upperBound + 20, from: 1, to: 15).map(\.1) == [.farAbove])
        var other = ZoneAlertEngine()
        _ = other.beginStep(target: zone, at: 0)
        #expect(feed(&other, zone.lowerBound - 20, from: 1, to: 15).map(\.1) == [.farBelow])
    }

    @Test("repeats come faster and turn far the longer it lasts")
    func escalation() throws {
        let zone = try target(3)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        let alerts = feed(&engine, zone.lowerBound - 5, from: 1, to: 130)
        let late = alerts.filter { $0.0 >= 70 }
        #expect(late.count >= 2)
        #expect(late[1].0 - late[0].0 == 10)
        #expect(alerts.last?.1 == .farBelow)
    }

    @Test("a big gap that is closing fast stays quiet, and alerts when the heart rate stalls")
    func slopeRule() throws {
        let zone = try target(4)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        // From 100 bpm up by 1 bpm a second: far below zone 4 but rising 10 bpm per 10 s.
        let climbing = (1...40).compactMap { t in
            engine.add(100 + Double(t), at: Double(t)).map { (t, $0) }
        }
        #expect(climbing.isEmpty)
        // Then it stalls well below the zone.
        #expect(!feed(&engine, 140, from: 41, to: 70).isEmpty)
    }

    @Test("a climb reported every 5 s stays quiet too, as a watch may report it")
    func slopeRuleSparse() throws {
        let zone = try target(4)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        // 100 bpm up by 2 bpm a second, one reading every 5 s.
        let climbing = stride(from: 3, through: 28, by: 5).compactMap { t in
            engine.add(100 + 2 * Double(t), at: Double(t)).map { (t, $0) }
        }
        #expect(climbing.isEmpty)
    }

    @Test("a wide gap waits for the slope at the start of a step, and not for longer than a slope window")
    func waitsForSlope() throws {
        let zone = try target(4)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        // One reading, far below, and nothing yet to say which way it is going: wait.
        #expect(engine.add(100, at: 3) == nil)
        // The next reading shows it flat, so it alerts (here 9 s into the step).
        #expect(engine.add(100, at: 9) == .farBelow)
        // A first reading that comes only after the slope window has nothing to wait for.
        var late = ZoneAlertEngine()
        _ = late.beginStep(target: zone, at: 0)
        #expect(late.add(100, at: 11) == .farBelow)
    }

    @Test("a wide gap after a resume waits for the slope too")
    func waitsAfterResume() throws {
        let zone = try target(4)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        _ = feed(&engine, zone.lowerBound + 3, from: 1, to: 60)
        engine.pause()
        // The resume: the first readings are held back for the smoothing window, then a climbing
        // heart rate far below the zone stays quiet.
        let climbing = stride(from: 100, through: 130, by: 5).compactMap { t in
            engine.add(100 + 2 * Double(t - 100), at: Double(t)).map { (t, $0) }
        }
        #expect(climbing.isEmpty)
    }

    @Test("a heart rate falling while below the zone is not excused by the slope rule")
    func fallingBelow() throws {
        let zone = try target(4)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        let alerts = (1...30).compactMap { t in
            engine.add(150 - Double(t) * 0.5, at: Double(t)).map { (t, $0) }
        }
        // The gap is wider than the zone, so the first second waits for the slope; a falling heart rate then alerts.
        #expect(alerts.first?.0 == 3)
    }

    @Test("a small gap alerts even when rising slowly")
    func smallGapAlertsWhileRising() throws {
        let zone = try target(4)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        let start = zone.lowerBound - 6
        let alerts = (1...20).compactMap { t in
            engine.add(start + Double(t) * 0.1, at: Double(t)).map { (t, $0) }
        }
        #expect(alerts.map(\.1).contains(.tooLow))
    }

    @Test("entering the zone from below alerts; a step that starts inside does not")
    func entering() throws {
        let zone = try target(4)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        let width = zone.upperBound - zone.lowerBound
        var alerts: [ZoneAlert] = []
        for t in 1...40 {
            let bpm = zone.lowerBound - 2.5 * width + Double(t) * (2.5 * width + 4) / 40
            if let alert = engine.add(bpm, at: Double(t)) { alerts.append(alert) }
        }
        #expect(alerts == [.backInZone])
    }

    @Test("a reading on a bound does not chatter")
    func hysteresis() throws {
        let zone = try target(3)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        // Out by 5, then hovering just under the bound: still out, never "back in".
        _ = feed(&engine, zone.lowerBound - 5, from: 1, to: 12)
        let hover = feed(&engine, zone.lowerBound - 0.5, from: 13, to: 30)
        #expect(!hover.map(\.1).contains(.backInZone))
    }

    @Test("a new step forgets the last one")
    func newStep() throws {
        let zone = try target(3)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        _ = feed(&engine, zone.lowerBound - 5, from: 1, to: 30)
        _ = engine.beginStep(target: zone, at: 31)
        // Inside at once: no "back in" for a step that started inside.
        #expect(feed(&engine, zone.lowerBound + 3, from: 32, to: 60).isEmpty)
    }

    @Test("after a pause the old readings are gone and the first readings are held back")
    func pause() throws {
        let zone = try target(3)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        // Far above the zone before the pause...
        _ = feed(&engine, zone.upperBound + 30, from: 1, to: 20)
        engine.pause()
        // ...and below it after: a lone reading doesn't alert, nor do the ones in the next 3 s,
        // and the earlier readings don't drag the mean up.
        let held = feed(&engine, zone.lowerBound - 5, from: 21, to: 23)
        #expect(held.isEmpty)
        let after = feed(&engine, zone.lowerBound - 5, from: 24, to: 40)
        #expect(after.map(\.1) == [.tooLow])
    }

    @Test("a target changed in the middle of a step is used from the next reading, without an alert")
    func updateTarget() throws {
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: nil, at: 0)
        #expect(feed(&engine, 100, from: 1, to: 30).isEmpty)
        // The zones arrive: the heart rate is far under zone 3, which is now a target.
        engine.updateTarget(try target(3))
        #expect(!feed(&engine, 100, from: 31, to: 60).isEmpty)
        // Same target again changes nothing.
        engine.updateTarget(try target(3))
        #expect(feed(&engine, 100, from: 61, to: 62).isEmpty)
    }

    @Test("the pace preset waits for the signal to stay out, and has no slope rule")
    func pacePreset() {
        var engine = ZoneAlertEngine(settings: .pace)
        // A target of 3.0 to 3.4 m/s; the runner is at 2.0 m/s from the start.
        _ = engine.beginStep(target: 3.0...3.4, at: 0)
        let alerts = (1...30).compactMap { t in
            engine.add(2.0 + Double(t) * 0.02, at: Double(t)).map { (t, $0) }
        }
        // Rising, but a pace has no slope rule: the first alert comes after the step's grace.
        #expect(alerts.first?.0 == 5)
        #expect(alerts.first?.1 == .farBelow)
        // Repeats at 10 s.
        #expect(alerts[1].0 - alerts[0].0 == 10)
    }
}
