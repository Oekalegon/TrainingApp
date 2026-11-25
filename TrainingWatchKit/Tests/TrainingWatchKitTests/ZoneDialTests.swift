import CoreGraphics
import Foundation
import Testing
import TrainingCore
@testable import TrainingWatchKit

@Suite("Zone dial (WATCH-118)")
struct ZoneDialTests {
    // Zones with resting 55 and maximum 190: zone 1 122.5-136, 2 136-149.5, 3 149.5-163, 4 163-176.5, 5 176.5-190.
    private let bands = ZoneBands(zones: WatchZones(settings: .init(
        effectiveDate: .distantPast, restingHeartRateBPM: 55, maxHeartRateBPM: 190)))!

    @Test("the position runs from 0 under zone 1 to 6 at the top of zone 5")
    func position() {
        #expect(bands.position(forHeartRate: 122.5) == 1)
        #expect(abs(bands.position(forHeartRate: 142.75) - 2.5) < 0.001)
        #expect(bands.position(forHeartRate: 190) == 6)
        #expect(bands.position(forHeartRate: 210) == 6)
        // Zone 0 spans one zone-1 width under zone 1 (13.5 bpm).
        #expect(abs(bands.position(forHeartRate: 115.75) - 0.5) < 0.001)
        #expect(bands.position(forHeartRate: 100) == 0)
        #expect(bands.position(forHeartRate: 0) == 0)
    }

    @Test("the position agrees with the zone a heart rate is in")
    func positionMatchesZone() {
        for bpm in stride(from: 90.0, through: 189, by: 1.5) {
            let zone = bands.zone(forHeartRate: bpm)
            #expect(Int(bands.position(forHeartRate: bpm).rounded(.down)) == min(zone, 6), "\(bpm)")
        }
    }

    /// A line 200 long.
    private let length = 200.0

    @Test("the zones are in order from the left, the same size, and the target three times as wide")
    func layout() {
        let spans = ZoneDial.spans(target: 3, length: length)
        let unit = length / 8
        for zone in 0...5 {
            #expect(abs(spans[zone].length - (zone == 3 ? 3 * unit : unit)) < 0.001, "zone \(zone)")
        }
        #expect(spans[0].start == 0 && abs(spans[5].end - length) < 0.001)
        for zone in 1...5 { #expect(abs(spans[zone].start - spans[zone - 1].end) < 0.001) }
    }

    @Test("a low target is a bit to the left of the middle, a high one to the right of it")
    func targetPlace() {
        func middle(_ target: Int) -> Double {
            let span = ZoneDial.spans(target: target, length: length)[target]
            return (span.start + span.end) / 2
        }
        #expect(middle(1) < length / 2 - 20)
        #expect(middle(5) > length / 2 + 20)
        for target in 1...4 { #expect(middle(target) < middle(target + 1)) }
    }

    @Test("the zones tile the line without gaps or overlap, for every target")
    func tiling() {
        for target in 1...5 {
            let spans = ZoneDial.spans(target: target, length: length)
            #expect(abs(spans.reduce(0) { $0 + $1.length } - length) < 0.001, "target \(target)")
        }
    }

    @Test("between two targets the layouts are blended, and a whole number gives its own")
    func blending() {
        let two = ZoneDial.spans(target: 2, length: length)
        let three = ZoneDial.spans(target: 3, length: length)
        #expect(ZoneDial.spans(target: 2.0, length: length) == two)
        let half = ZoneDial.spans(target: 2.5, length: length)
        for zone in 0...5 {
            #expect(abs(half[zone].start - (two[zone].start + three[zone].start) / 2) < 0.001)
            #expect(abs(half[zone].end - (two[zone].end + three[zone].end) / 2) < 0.001)
        }
    }

    @Test("a position along the zones is a distance inside its zone's span")
    func distances() {
        let total = length
        let spans = ZoneDial.spans(target: 2, length: length)
        // Zones 0 and 1 are an eighth each: zone 2 starts at 2/8 and is three eighths wide.
        #expect(abs(ZoneDial.distance(forPosition: 2.5, in: spans) - total * 3.5 / 8) < 0.001)
        #expect(abs(ZoneDial.distance(forPosition: 2.0, in: spans) - total * 2 / 8) < 0.001)
        // Zone 0 starts the line, and 6.0 (the top of zone 5) ends it.
        #expect(ZoneDial.distance(forPosition: 0, in: spans) == 0)
        #expect(abs(ZoneDial.distance(forPosition: 6, in: spans) - total) < 0.001)
        // Rising heart rate only moves forward along the ring.
        var last = -1.0
        for position in stride(from: 0.0, through: 6, by: 0.1) {
            let distance = ZoneDial.distance(forPosition: position, in: spans)
            #expect(distance >= last)
            last = distance
        }
    }

    @Test("a target's zone: the zone itself, where a stretch starts, or the middle of a bpm range")
    func targetZone() throws {
        func zone(_ target: IntensityTarget) throws -> Int {
            let step = WorkoutStep(kind: .work, goal: .time(60), target: target)
            return try #require(StepHeartRateTarget(step: step, bands: bands)).zone
        }
        #expect(try zone(.heartRateZone(4)) == 4)
        #expect(try zone(.heartRateZoneRange(3.5...4.0)) == 3)
        #expect(try zone(.heartRateRange(150, 160)) == 3)
    }

    @Test("the dial's status leaves the target only beyond a margin of a tenth of its width, at least 1 bpm")
    func status() throws {
        let step = WorkoutStep(kind: .work, goal: .time(60), target: .heartRateZone(3))
        let target = try #require(StepHeartRateTarget(step: step, bands: bands))
        // Zone 3 is 149.5 to 163: 13.5 wide, so 1.35 bpm of margin.
        #expect(target.status(forHeartRate: 156) == .inside)
        #expect(target.status(forHeartRate: 149.5 - 1.0) == .inside)
        #expect(target.status(forHeartRate: 149.5 - 2.0) == .below)
        #expect(target.status(forHeartRate: 163 + 1.0) == .inside)
        #expect(target.status(forHeartRate: 163 + 2.0) == .above)
        // A narrow target has at least 1 bpm.
        let narrow = try #require(StepHeartRateTarget(
            step: WorkoutStep(kind: .work, goal: .time(60), target: .heartRateRange(150, 152)), bands: bands))
        #expect(narrow.status(forHeartRate: 149.2) == .inside)
        #expect(narrow.status(forHeartRate: 148.5) == .below)
    }

    @Test("a target as a stretch of the zones: a whole zone, part of one, or bpm")
    func targetPositions() throws {
        func positions(_ target: IntensityTarget) throws -> ClosedRange<Double> {
            let step = WorkoutStep(kind: .work, goal: .time(60), target: target)
            return try #require(StepHeartRateTarget(step: step, bands: bands)).positions(in: bands)
        }
        let whole = try positions(.heartRateZone(4))
        #expect(abs(whole.lowerBound - 4) < 0.001 && abs(whole.upperBound - 5) < 0.001)
        let half = try positions(.heartRateZoneRange(4.0...4.5))
        #expect(abs(half.lowerBound - 4) < 0.001 && abs(half.upperBound - 4.5) < 0.001)
        // 150 to 156.25 bpm in zone 3 (149.5 to 163): 3.04 to 3.5.
        let bpm = try positions(.heartRateRange(150, 156.25))
        #expect(abs(bpm.lowerBound - 3.037) < 0.01 && abs(bpm.upperBound - 3.5) < 0.01)
    }

    @Test("the position text rounds down and never shows zone 6")
    func positionText() {
        #expect(ZoneDialText.positionText(2.3) == "Z 2.3")
        #expect(ZoneDialText.positionText(2.99) == "Z 2.9")
        #expect(ZoneDialText.positionText(0.4) == "Z <1")
        #expect(ZoneDialText.positionText(6) == "Z 5.9")
        #expect(ZoneDialText.positionValue(2.3) == "2.3")
        #expect(ZoneDialText.positionValue(0.4) == "<1")
    }

    @Test("the total time always has the hours")
    func totalTime() {
        #expect(ZoneDialText.totalTimeText(0) == "0:00:00")
        #expect(ZoneDialText.totalTimeText(59.9) == "0:00:59")
        #expect(ZoneDialText.totalTimeText(24 * 60 + 15) == "0:24:15")
        #expect(ZoneDialText.totalTimeText(3599) == "0:59:59")
        #expect(ZoneDialText.totalTimeText(3600 + 24 * 60 + 15) == "1:24:15")
        #expect(ZoneDialText.totalTimeText(-3) == "0:00:00")
    }

    @Test("with the wrist down the total time has no seconds")
    func totalTimeWithoutSeconds() {
        #expect(ZoneDialText.totalTimeText(59.9, showsSeconds: false) == "0:00")
        #expect(ZoneDialText.totalTimeText(24 * 60 + 15, showsSeconds: false) == "0:24")
        #expect(ZoneDialText.totalTimeText(3600 + 24 * 60 + 59, showsSeconds: false) == "1:24")
    }

    @Test("the step lines read as VoiceOver should say them")
    func lines() {
        let work = WorkoutStep(kind: .work, goal: .time(90), target: .heartRateZone(2))
        let recover = WorkoutStep(kind: .recovery, goal: .time(240), target: .heartRateZone(1))
        let locale = Locale(identifier: "en_NL")
        #expect(ZoneDialText.stepLine(work, locale: locale) == "WORK 1:30 in Zone 2")
        #expect(ZoneDialText.stepLine(recover, locale: locale) == "RECOVER 4:00 in Zone 1")
        let km = WorkoutStep(kind: .cooldown, goal: .distance(1000), target: .heartRateZoneRange(1.0...1.5))
        #expect(ZoneDialText.stepLine(km, locale: locale) == "COOL-DOWN 1 km in Zone 1.0-1.5")
        let engine = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [work, recover], repetitions: 12)])
        #expect(ZoneDialText.placeLine(engine.current!, of: engine.steps.count) == "INTERVAL 1 of 12")
        #expect(ZoneDialText.place(of: engine.current!, in: engine.steps.count) == .interval(1, of: 12))
        #expect(ZoneDialText.place(of: engine.current!, in: engine.steps.count).text == "1/12")
        #expect(ZoneDialText.place(of: engine.current!, in: engine.steps.count).isRepeat)
        let single = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [work])])
        #expect(ZoneDialText.placeLine(single.current!, of: 1) == "STEP 1 of 1")
        // Every step has a number: the interval in a repeat, the step's place otherwise.
        #expect(ZoneDialText.place(of: single.current!, in: 1) == .step(1, of: 1))
        #expect(ZoneDialText.place(of: single.current!, in: 1).text == "1/1")
        #expect(!ZoneDialText.place(of: single.current!, in: 1).isRepeat)
    }
}
