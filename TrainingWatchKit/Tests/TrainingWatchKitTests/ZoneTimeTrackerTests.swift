import Testing
@testable import TrainingWatchKit

@Suite("ZoneTimeTracker (WATCH-132)")
struct ZoneTimeTrackerTests {
    @Test("the time between two readings goes to the zone of the earlier one")
    func between() {
        var tracker = ZoneTimeTracker()
        #expect(tracker.fractions == nil)
        tracker.add(zone: 2, atElapsed: 0)
        tracker.add(zone: 3, atElapsed: 6)
        tracker.add(zone: 3, atElapsed: 8)
        #expect(tracker.seconds[2] == 6)
        #expect(tracker.seconds[3] == 2)
        #expect(tracker.fractions?[2] == 0.75)
    }

    @Test("a long gap counts only the maximum, and a zone outside 0 to 5 is clamped")
    func gaps() {
        var tracker = ZoneTimeTracker()
        tracker.add(zone: 1, atElapsed: 0)
        tracker.add(zone: 9, atElapsed: 100)
        tracker.add(zone: 9, atElapsed: 103)
        #expect(tracker.seconds[1] == ZoneTimeTracker.maximumGap)
        #expect(tracker.seconds[5] == 3)
    }

    @Test("reset forgets the run before")
    func reset() {
        var tracker = ZoneTimeTracker()
        tracker.add(zone: 1, atElapsed: 0)
        tracker.add(zone: 1, atElapsed: 4)
        tracker.reset()
        #expect(tracker.fractions == nil)
        tracker.add(zone: 2, atElapsed: 50)
        #expect(tracker.fractions == nil)
    }

    @Test("the spoken histogram names the zones with time and rounds to whole percents")
    func spoken() {
        #expect(ZoneTimeText.spoken(nil) == "no time measured yet")
        #expect(ZoneTimeText.spoken([0.1, 0.0, 0.6, 0.3004, 0.0, 0.0]) == "below zone 1 10 percent, zone 2 60 percent, zone 3 30 percent")
        #expect(ZoneTimeText.spoken([0.001, 0, 0, 0, 0, 0]) == "no time measured yet")
    }

    @Test("time in a zone is read per zone, and time since entering counts from the first reading in the zone (WATCH-135)")
    func perZone() {
        var tracker = ZoneTimeTracker()
        #expect(tracker.secondsSinceEntering(atElapsed: 5) == nil)
        tracker.add(zone: 2, atElapsed: 0)
        tracker.add(zone: 3, atElapsed: 6)
        tracker.add(zone: 3, atElapsed: 10)
        #expect(tracker.seconds(inZone: 2) == 6)
        #expect(tracker.seconds(inZone: 3) == 4)
        #expect(tracker.seconds(inZone: 5) == 0)
        #expect(tracker.secondsSinceEntering(atElapsed: 12) == 6)
        // Back into zone 2: the stretch starts over, the total keeps what it had.
        tracker.add(zone: 2, atElapsed: 14)
        #expect(tracker.secondsSinceEntering(atElapsed: 15) == 1)
        #expect(tracker.seconds(inZone: 3) == 8)
    }
}
