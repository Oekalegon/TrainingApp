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

    @Test("a sector is centred on the top for the target, and the others follow clockwise")
    func sectors() {
        #expect(ZoneDial.sectorCenter(zone: 2, target: 2) == 0)
        #expect(ZoneDial.sectorCenter(zone: 3, target: 2) == 60)
        #expect(ZoneDial.sectorCenter(zone: 1, target: 2) == -60)
        // Zone 0 is two sectors to the left of zone 2, the drawing's lower left.
        #expect(ZoneDial.sectorCenter(zone: 0, target: 2) == -120)
        #expect(ZoneDial.sectorCenter(zone: 5, target: 2) == 180)
    }

    @Test("a position's angle is inside its zone's sector, and 2.3 against a zone 2 target is just left of the top")
    func angles() {
        #expect(abs(ZoneDial.angle(forPosition: 2.3, target: 2) - (-12)) < 0.001)
        #expect(ZoneDial.angle(forPosition: 2.5, target: 2) == 0)
        for zone in 0...5 {
            for fraction in [0.0, 0.25, 0.99] {
                let angle = ZoneDial.angle(forPosition: Double(zone) + fraction, target: 3)
                let center = ZoneDial.sectorCenter(zone: zone, target: 3)
                #expect(abs(angle - center) <= 30.001)
            }
        }
    }

    @Test("a new target turns the ring by a sector")
    func turning() {
        let before = ZoneDial.angle(forPosition: 2.3, target: 2)
        let after = ZoneDial.angle(forPosition: 2.3, target: 3)
        #expect(abs((before - after) - 60) < 0.001)
    }

    @Test("the edge point at the top, right, bottom and left of a plain rectangle")
    func edges() {
        let size = CGSize(width: 200, height: 300)
        let top = ZoneDial.edgePoint(atAngle: 0, size: size, cornerRadius: 0)
        #expect(abs(top.point.x - 100) < 0.001 && abs(top.point.y) < 0.001 && abs(top.outward) < 0.001)
        let right = ZoneDial.edgePoint(atAngle: 90, size: size, cornerRadius: 0)
        #expect(abs(right.point.x - 200) < 0.001 && abs(right.point.y - 150) < 0.001 && abs(right.outward - 90) < 0.001)
        let bottom = ZoneDial.edgePoint(atAngle: 180, size: size, cornerRadius: 0)
        #expect(abs(bottom.point.y - 300) < 0.001 && abs(abs(bottom.outward) - 180) < 0.001)
        let left = ZoneDial.edgePoint(atAngle: -90, size: size, cornerRadius: 0)
        #expect(abs(left.point.x) < 0.001 && abs(left.outward + 90) < 0.001)
    }

    @Test("a rounded corner pulls the edge in, and faces diagonally")
    func corner() {
        let size = CGSize(width: 200, height: 200)
        // The diagonal to the top right: a plain corner is at (200, 0); a radius of 40 is 11.7 in from it.
        let square = ZoneDial.edgePoint(atAngle: 45, size: size, cornerRadius: 0)
        let rounded = ZoneDial.edgePoint(atAngle: 45, size: size, cornerRadius: 40)
        #expect(abs(square.point.x - 200) < 0.001)
        let pulledIn = (40 * (2.0.squareRoot() - 1)) / 2.0.squareRoot()
        #expect(abs(rounded.point.x - (200 - pulledIn)) < 0.01)
        #expect(abs(rounded.point.y - pulledIn) < 0.01)
        #expect(abs(rounded.outward - 45) < 0.01)
    }

    @Test("every edge point of a rounded rectangle is inside it, and its normal is a unit direction")
    func insideTheShape() {
        let size = CGSize(width: 205, height: 251)
        let radius = 50.0
        for angle in stride(from: -180.0, through: 180, by: 3) {
            let edge = ZoneDial.edgePoint(atAngle: angle, size: size, cornerRadius: radius)
            #expect(edge.point.x >= -0.001 && edge.point.x <= 205.001 && edge.point.y >= -0.001 && edge.point.y <= 251.001)
            // In a corner, the point is `radius` from the corner circle's middle.
            let dx = Double(edge.point.x) - 102.5, dy = Double(edge.point.y) - 125.5
            if abs(dx) > 102.5 - radius, abs(dy) > 125.5 - radius {
                let cx = (dx < 0 ? -1.0 : 1.0) * (102.5 - radius), cy = (dy < 0 ? -1.0 : 1.0) * (125.5 - radius)
                #expect(abs(hypot(dx - cx, dy - cy) - radius) < 0.01, "\(angle)")
            }
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

    @Test("the step lines read as on the drawing")
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
        #expect(ZoneDialText.nextLine(engine, locale: locale) == "NEXT: RECOVER 4:00 in Zone 1")
        let single = WorkoutStepEngine(blocks: [WorkoutBlock(steps: [work])])
        #expect(ZoneDialText.placeLine(single.current!, of: 1) == "STEP 1 of 1")
        #expect(ZoneDialText.nextLine(single, locale: locale) == "LAST STEP")
    }
}
