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

    // A circle of radius 100 round (100, 120), open for 80 degrees at the bottom.
    private let outline = ZoneDial.Outline(center: CGPoint(x: 100, y: 120), radius: 100, gapAngle: 80)

    @Test("the outline's length is the circle's arc without the gap")
    func outlineLength() {
        #expect(abs(outline.totalLength - 100 * 280 * Double.pi / 180) < 0.001)
        // No gap: the whole circle.
        let closed = ZoneDial.Outline(center: .zero, radius: 10, gapAngle: 0)
        #expect(abs(closed.totalLength - 2 * Double.pi * 10) < 0.001)
    }

    @Test("the outline starts at the lower left and runs clockwise over the top to the lower right")
    func outlinePoints() {
        let start = outline.point(at: 0)
        // 40 degrees either side of the bottom: left of the middle and below it.
        #expect(abs(start.point.x - (100 - 100 * sin(40 * .pi / 180))) < 0.001)
        #expect(abs(start.point.y - (120 + 100 * cos(40 * .pi / 180))) < 0.001)
        #expect(abs(start.outward - 220) < 0.001)
        // A quarter of the way along it is on the left, facing left.
        let left = outline.point(at: 100 * 50 * Double.pi / 180)
        #expect(abs(left.point.x) < 0.001 && abs(left.point.y - 120) < 0.001 && abs(left.outward - 270) < 0.001)
        // Half way is the top, facing up.
        let top = outline.point(at: outline.totalLength / 2)
        #expect(abs(top.point.x - 100) < 0.001 && abs(top.point.y - 20) < 0.001)
        #expect(min(top.outward, 360 - top.outward) < 0.001)
        // The end is at the lower right, mirroring the start.
        let end = outline.point(at: outline.totalLength)
        #expect(abs(end.point.x - (100 + 100 * sin(40 * .pi / 180))) < 0.001)
        #expect(abs(end.point.y - start.point.y) < 0.001)
        #expect(abs(end.outward - 140) < 0.001)
        // Past the ends it stays at the ends.
        #expect(outline.point(at: -10).point == start.point)
        #expect(outline.point(at: outline.totalLength + 10).point == end.point)
    }

    @Test("every point of the outline is on the circle, and none is in the gap at the bottom")
    func outlineShape() {
        for index in 0...300 {
            let edge = outline.point(at: outline.totalLength * Double(index) / 300)
            #expect(abs(hypot(Double(edge.point.x) - 100, Double(edge.point.y) - 120) - 100) < 0.001)
            // The gap is 140 to 220 degrees: nothing between them.
            #expect(!(edge.outward > 140.01 && edge.outward < 219.99), "\(index): \(edge.outward)")
        }
    }

    @Test("the gap is held between nothing and almost the whole circle")
    func gapLimits() {
        #expect(ZoneDial.Outline(center: .zero, radius: 10, gapAngle: -5).gapAngle == 0)
        #expect(ZoneDial.Outline(center: .zero, radius: 10, gapAngle: 900).gapAngle == 340)
        #expect(ZoneDial.Outline(center: .zero, radius: -3, gapAngle: 80).totalLength == 0)
    }

    @Test("the target has its own stretch, the lower zones come before it and the higher ones after")
    func layout() {
        let total = outline.totalLength
        let spans = ZoneDial.spans(target: 3, outline: outline)
        #expect(abs(spans[3].start - total * 0.35) < 0.001 && abs(spans[3].end - total * 0.65) < 0.001)
        // Below: zones 0, 1 and 2 in order from the start, zone 0 half the size of the others.
        #expect(spans[0].start == 0 && abs(spans[2].end - total * 0.35) < 0.001)
        #expect(abs(spans[1].start - spans[0].end) < 0.001 && abs(spans[2].start - spans[1].end) < 0.001)
        #expect(abs(spans[0].length * 2 - spans[1].length) < 0.001)
        #expect(abs(spans[1].length - spans[2].length) < 0.001)
        // Above: zones 4 and 5, equal, the last ending at the gap.
        #expect(abs(spans[4].start - total * 0.65) < 0.001)
        #expect(abs(spans[5].end - total) < 0.001)
        #expect(abs(spans[4].length - spans[5].length) < 0.001)
    }

    @Test("with zone 1 as the target, zone 0 has the whole lower stretch at full size; with zone 5, nothing is above")
    func edgeTargets() {
        let total = outline.totalLength
        let low = ZoneDial.spans(target: 1, outline: outline)
        #expect(low[0] == ZoneDial.Span(start: 0, end: total * 0.35))
        #expect(abs(low[2].length - total * 0.35 / 4) < 0.001)
        let high = ZoneDial.spans(target: 5, outline: outline)
        #expect(abs(high[0].length * 2 - high[1].length) < 0.001)
        #expect(abs(high[4].end - total * 0.35) < 0.001)
        #expect(abs(high[5].length - total * 0.30) < 0.001)
    }

    @Test("the zones tile the ring without gaps or overlap, for every target")
    func tiling() {
        for target in 1...5 {
            let spans = ZoneDial.spans(target: target, outline: outline)
            let covered = spans.reduce(0) { $0 + $1.length }
            // Everything is covered except the stretch for the zones above a zone 5 target.
            let expected = target == 5 ? outline.totalLength * 0.65 : outline.totalLength
            #expect(abs(covered - expected) < 0.001, "target \(target)")
        }
    }

    @Test("between two targets the layouts are blended, and a whole number gives its own")
    func blending() {
        let two = ZoneDial.spans(target: 2, outline: outline)
        let three = ZoneDial.spans(target: 3, outline: outline)
        #expect(ZoneDial.spans(target: 2.0, outline: outline) == two)
        let half = ZoneDial.spans(target: 2.5, outline: outline)
        for zone in 0...5 {
            #expect(abs(half[zone].start - (two[zone].start + three[zone].start) / 2) < 0.001)
            #expect(abs(half[zone].end - (two[zone].end + three[zone].end) / 2) < 0.001)
        }
    }

    @Test("a position along the zones is a distance inside its zone's span")
    func distances() {
        let total = outline.totalLength
        let spans = ZoneDial.spans(target: 2, outline: outline)
        // 2.5: the middle of the target's stretch.
        #expect(abs(ZoneDial.distance(forPosition: 2.5, in: spans) - total * 0.5) < 0.001)
        #expect(abs(ZoneDial.distance(forPosition: 2.0, in: spans) - total * 0.35) < 0.001)
        // Zone 0 starts the ring, and 6.0 (the top of zone 5) ends it at the gap.
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
        let single = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [work])])
        #expect(ZoneDialText.placeLine(single.current!, of: 1) == "STEP 1 of 1")
    }
}
