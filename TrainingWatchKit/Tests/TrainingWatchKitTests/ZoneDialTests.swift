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

    private let outline = ZoneDial.Outline(size: CGSize(width: 200, height: 250), cornerRadius: 50)

    @Test("the outline's lengths add up: three sides, four corner arcs")
    func outlineLengths() {
        let arc = 50 * Double.pi / 2
        #expect(abs(outline.leftLength - (arc + 150)) < 0.001)
        #expect(abs(outline.topLength - (2 * arc + 100)) < 0.001)
        #expect(abs(outline.rightLength - (150 + arc)) < 0.001)
        #expect(abs(outline.totalLength - (outline.leftLength + outline.topLength + outline.rightLength)) < 0.001)
    }

    @Test("the outline starts at the bottom left, goes up the left side, across the top and down the right")
    func outlinePoints() {
        let start = outline.point(at: 0)
        #expect(abs(start.point.x - 50) < 0.001 && abs(start.point.y - 250) < 0.001)
        #expect(abs(start.outward - 180) < 0.001)
        // Up the left side: facing left.
        let side = outline.point(at: 50 * .pi / 2 + 75)
        #expect(abs(side.point.x) < 0.001 && abs(side.point.y - 125) < 0.001 && side.outward == 270)
        // The middle of the top: facing up.
        let top = outline.point(at: outline.leftLength + outline.topLength / 2)
        #expect(abs(top.point.x - 100) < 0.001 && abs(top.point.y) < 0.001 && abs(top.outward) < 0.001)
        // Down the right side: facing right.
        let right = outline.point(at: outline.leftLength + outline.topLength + 75)
        #expect(abs(right.point.x - 200) < 0.001 && abs(right.point.y - 125) < 0.001 && right.outward == 90)
        // The end: the bottom right, where the bottom edge starts, facing down.
        let end = outline.point(at: outline.totalLength)
        #expect(abs(end.point.x - 150) < 0.001 && abs(end.point.y - 250) < 0.001 && abs(end.outward - 180) < 0.001)
        // Past the ends it stays at the ends.
        #expect(outline.point(at: -10).point == start.point)
        #expect(outline.point(at: outline.totalLength + 10).point == end.point)
    }

    @Test("the outline stays inside the screen and on its rounded edge")
    func outlineShape() {
        for index in 0...200 {
            let edge = outline.point(at: outline.totalLength * Double(index) / 200)
            #expect(edge.point.x >= -0.001 && edge.point.x <= 200.001 && edge.point.y >= -0.001 && edge.point.y <= 250.001)
            // In a corner, it is `radius` from the corner circle's middle.
            let x = Double(edge.point.x), y = Double(edge.point.y)
            let cx = x < 50 ? 50.0 : (x > 150 ? 150.0 : x), cy = y < 50 ? 50.0 : (y > 200 ? 200.0 : y)
            if (x < 50 || x > 150), (y < 50 || y > 200) { #expect(abs(hypot(x - cx, y - cy) - 50) < 0.01) }
        }
    }

    @Test("the target has the whole top, the lower zones the left and the higher ones the right")
    func layout() {
        let spans = ZoneDial.spans(target: 3, outline: outline)
        #expect(spans[3] == ZoneDial.Span(start: outline.leftLength, end: outline.leftLength + outline.topLength))
        // Left: zones 0, 1 and 2 in order along the left side, zone 0 half the size of the others.
        #expect(spans[0].start == 0 && abs(spans[2].end - outline.leftLength) < 0.001)
        #expect(abs(spans[1].start - spans[0].end) < 0.001 && abs(spans[2].start - spans[1].end) < 0.001)
        #expect(abs(spans[0].length * 2 - spans[1].length) < 0.001)
        #expect(abs(spans[1].length - spans[2].length) < 0.001)
        // Right: zones 4 and 5, the nearer to the top first, equal.
        #expect(abs(spans[4].start - (outline.leftLength + outline.topLength)) < 0.001)
        #expect(abs(spans[5].end - outline.totalLength) < 0.001)
        #expect(abs(spans[4].length - spans[5].length) < 0.001)
    }

    @Test("with zone 1 as the target, zone 0 has the whole left side at full size; with zone 5, the right side is empty")
    func edgeTargets() {
        let low = ZoneDial.spans(target: 1, outline: outline)
        #expect(low[0] == ZoneDial.Span(start: 0, end: outline.leftLength))
        #expect(abs(low[2].length - outline.rightLength / 4) < 0.001)
        let high = ZoneDial.spans(target: 5, outline: outline)
        #expect(abs(high[0].length * 2 - high[1].length) < 0.001)
        #expect(abs(high[4].end - outline.leftLength) < 0.001)
        #expect(high[5].length == outline.topLength)
    }

    @Test("the zones tile the outline without gaps or overlap, for every target")
    func tiling() {
        for target in 1...5 {
            let spans = ZoneDial.spans(target: target, outline: outline)
            let covered = spans.reduce(0) { $0 + $1.length }
            // Everything is covered except the right side when nothing is above the target.
            let expected = target == 5 ? outline.totalLength - outline.rightLength : outline.totalLength
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
        let spans = ZoneDial.spans(target: 2, outline: outline)
        // 2.5: the middle of the top, which the target has to itself.
        #expect(abs(ZoneDial.distance(forPosition: 2.5, in: spans) - (outline.leftLength + outline.topLength / 2)) < 0.001)
        #expect(abs(ZoneDial.distance(forPosition: 2.0, in: spans) - outline.leftLength) < 0.001)
        // Zone 0 starts the ring, and 6.0 (the top of zone 5) ends it.
        #expect(ZoneDial.distance(forPosition: 0, in: spans) == 0)
        #expect(abs(ZoneDial.distance(forPosition: 6, in: spans) - outline.totalLength) < 0.001)
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
