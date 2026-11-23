import Foundation
import Testing
import TrainingCore
@testable import TrainingWatchKit

@Suite("ZoneAlertEngine (WATCH-106)")
struct ZoneAlertEngineTests {
    private let bands = ZoneBands(zones: WatchZones(settings: .init(
        effectiveDate: .distantPast, restingHeartRateBPM: 55, maxHeartRateBPM: 190)))!

    private func target(_ zone: Int) throws -> StepHeartRateTarget {
        let step = WorkoutStep(kind: .work, goal: .time(60), target: .heartRateZone(zone))
        return try #require(StepHeartRateTarget(step: step, bands: bands))
    }

    /// Feeds one reading per second from `from` to `to` (seconds), all at `bpm`, and collects the alerts.
    private func feed(
        _ engine: inout ZoneAlertEngine, bpm: Double, from: Int, to: Int
    ) -> [(Int, ZoneAlert)] {
        (from...to).compactMap { t in engine.add(heartRate: bpm, at: Double(t)).map { (t, $0) } }
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
        #expect(feed(&engine, bpm: 60, from: 1, to: 60).isEmpty)
    }

    @Test("a heart rate inside the zone stays quiet, also just outside it within the hysteresis")
    func quiet() throws {
        let zone = try target(3)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        #expect(feed(&engine, bpm: zone.bpm.lowerBound + 2, from: 1, to: 60).isEmpty)
        #expect(feed(&engine, bpm: zone.bpm.lowerBound - 2, from: 61, to: 120).isEmpty)
    }

    @Test("under the zone: too low after the start grace, then repeated, and back in zone once")
    func tooLowThenBack() throws {
        let zone = try target(3)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        let low = zone.bpm.lowerBound - 5
        let alerts = feed(&engine, bpm: low, from: 1, to: 50)
        #expect(alerts.map(\.1) == [.tooLow, .tooLow, .tooLow])
        #expect(alerts.first!.0 >= 8)
        #expect(alerts[1].0 - alerts[0].0 == 20)
        let back = feed(&engine, bpm: zone.bpm.lowerBound + 3, from: 51, to: 80)
        #expect(back.map(\.1) == [.backInZone])
    }

    @Test("over the zone is too high")
    func tooHigh() throws {
        let zone = try target(3)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        #expect(feed(&engine, bpm: zone.bpm.upperBound + 5, from: 1, to: 15).map(\.1) == [.tooHigh])
    }

    @Test("well outside the zone is the far alert, above and below")
    func far() throws {
        let zone = try target(3)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        #expect(feed(&engine, bpm: zone.bpm.upperBound + 20, from: 1, to: 15).map(\.1) == [.farAbove])
        var other = ZoneAlertEngine()
        _ = other.beginStep(target: zone, at: 0)
        #expect(feed(&other, bpm: zone.bpm.lowerBound - 20, from: 1, to: 15).map(\.1) == [.farBelow])
    }

    @Test("repeats come faster and turn far the longer it lasts")
    func escalation() throws {
        let zone = try target(3)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        let alerts = feed(&engine, bpm: zone.bpm.lowerBound - 5, from: 1, to: 130)
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
            engine.add(heartRate: 100 + Double(t), at: Double(t)).map { (t, $0) }
        }
        #expect(climbing.isEmpty)
        // Then it stalls well below the zone.
        let stalled = feed(&engine, bpm: 140, from: 41, to: 70)
        #expect(!stalled.isEmpty)
    }

    @Test("a small gap alerts even when rising")
    func smallGapAlertsWhileRising() throws {
        let zone = try target(4)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        let start = zone.bpm.lowerBound - 6
        let alerts = (1...20).compactMap { t in
            engine.add(heartRate: start + Double(t) * 0.1, at: Double(t)).map { (t, $0) }
        }
        #expect(alerts.map(\.1).contains(.tooLow))
    }

    @Test("entering the zone from below alerts; a step that starts inside does not")
    func entering() throws {
        let zone = try target(4)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        let width = zone.bpm.upperBound - zone.bpm.lowerBound
        var alerts: [ZoneAlert] = []
        for t in 1...40 {
            let bpm = zone.bpm.lowerBound - 2.5 * width + Double(t) * (2.5 * width + 4) / 40
            if let alert = engine.add(heartRate: bpm, at: Double(t)) { alerts.append(alert) }
        }
        #expect(alerts == [.backInZone])
    }

    @Test("a reading on a bound does not chatter")
    func hysteresis() throws {
        let zone = try target(3)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        // Out by 5, then hovering 1 bpm under the bound: still out, never "back in".
        _ = feed(&engine, bpm: zone.bpm.lowerBound - 5, from: 1, to: 12)
        let hover = feed(&engine, bpm: zone.bpm.lowerBound - 1, from: 13, to: 30)
        #expect(!hover.map(\.1).contains(.backInZone))
    }

    @Test("a new step forgets the last one, and a pause forgets old readings")
    func reset() throws {
        let zone = try target(3)
        var engine = ZoneAlertEngine()
        _ = engine.beginStep(target: zone, at: 0)
        _ = feed(&engine, bpm: zone.bpm.lowerBound - 5, from: 1, to: 30)
        _ = engine.beginStep(target: zone, at: 31)
        // Inside at once: no "back in" for a step that started inside.
        #expect(feed(&engine, bpm: zone.bpm.lowerBound + 3, from: 32, to: 60).isEmpty)
        engine.pause()
        #expect(engine.add(heartRate: zone.bpm.lowerBound + 3, at: 400) == nil)
    }
}
