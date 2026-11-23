import Foundation
import Testing
import TrainingCore
@testable import TrainingWatchKit

/// The 4 × 90 s alert-test workout and its GPX track (`Tools/make-interval-gpx.py --alert`): the
/// track must follow the workout, and replayed through `ZoneAlertEngine` it must give each kind of
/// alert, so the simulator run shows them (WATCH-106).
@Suite("Alert test workout and its GPX track (WATCH-106)")
struct AlertTestTrackTests {
    private let bands = ZoneBands(zones: WatchZones(settings: .init(
        effectiveDate: .distantPast, restingHeartRateBPM: 55, maxHeartRateBPM: 190)))!

    private var track: [GPXTrackPoint] {
        get throws {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            let text = try String(contentsOf: root.appending(path: "Tools/TestTracks/alert-test.gpx"), encoding: .utf8)
            return GPXTrack.points(in: text)
        }
    }

    /// Each step's start second and heart-rate target, from the step engine.
    private var steps: [(start: Double, target: ClosedRange<Double>?)] {
        var start = 0.0
        return WorkoutStepEngine(blocks: TestWorkouts.alertTest).steps.map { step in
            defer { if case .time(let seconds) = step.step.goal { start += seconds } }
            return (start, StepHeartRateTarget(step: step.step, bands: bands)?.bpm)
        }
    }

    /// The alerts the engine gives for the track, per step number, as the recorder would run it.
    private func alertsByStep() throws -> [Int: [ZoneAlert]] {
        let points = try track
        let steps = self.steps
        var engine = ZoneAlertEngine()
        var result: [Int: [ZoneAlert]] = [:]
        var current = -1
        let origin = points[0].time
        for point in points {
            let time = point.time.timeIntervalSince(origin)
            while current + 1 < steps.count, steps[current + 1].start <= time {
                current += 1
                _ = engine.beginStep(target: steps[current].target, at: time)
            }
            if let bpm = point.heartRate, let alert = engine.add(bpm, at: time) { result[current, default: []].append(alert) }
        }
        return result
    }

    @Test("the track lasts as long as the workout")
    func duration() throws {
        let points = try track
        #expect(steps.count == 10)
        #expect(points.count == 841)
        #expect(points.last!.time.timeIntervalSince(points.first!.time) == 840)
    }

    @Test("a step that stays in its zone gives only a back-in-zone alert, once its climb or fall is over")
    func quietSteps() throws {
        let alerts = try alertsByStep()
        for step in [0, 1, 2] { #expect(alerts[step] == [.backInZone], "step \(step)") }
    }

    @Test("a hard step that drifts above its zone gives too high and then far above, and back in at the end")
    func above() throws {
        let alerts = try #require(try alertsByStep()[3])
        #expect(alerts.contains(.tooHigh))
        #expect(alerts.contains(.farAbove))
        #expect(alerts.last == .backInZone)
    }

    @Test("a hard step that drops below gives too low and then far below, and back in at the end")
    func below() throws {
        let alerts = try #require(try alertsByStep()[5])
        #expect(alerts.contains(.tooLow))
        #expect(alerts.contains(.farBelow))
        #expect(alerts.last == .backInZone)
    }

    @Test("easy steps that leave zone 2 give too high and too low, and come back")
    func easy() throws {
        let alerts = try alertsByStep()
        #expect(alerts[4]?.contains(.tooHigh) == true)
        #expect(alerts[4]?.last == .backInZone)
        #expect(alerts[6]?.contains(.tooLow) == true)
        #expect(alerts[6]?.last == .backInZone)
    }

    @Test("steps that never reach their zone repeat the alert")
    func repeats() throws {
        let alerts = try alertsByStep()
        #expect((alerts[7] ?? []).filter { $0 == .tooLow }.count >= 3)
        #expect((alerts[8] ?? []).filter { $0 == .tooHigh }.count >= 3)
    }
}
