import Foundation
import Testing
@testable import TrainingWatchKit

@Suite("RunQuantity (WATCH-135)")
struct RunQuantityTests {
    @Test("the tracker keeps current, average, lowest, highest and median")
    func statistics() {
        var tracker = RunQuantityTracker()
        #expect(tracker.value(.current) == nil)
        for value in [170.0, 180, 160, 190] { tracker.add(value) }
        #expect(tracker.value(.current) == 190)
        #expect(tracker.value(.average) == 175)
        #expect(tracker.value(.minimum) == 160)
        #expect(tracker.value(.maximum) == 190)
        #expect(tracker.value(.median) == 175)
        tracker.add(100)
        #expect(tracker.value(.median) == 170)
    }

    @Test("the sorted window drops the oldest reading, also when it equals another, and the median follows")
    func slidingMedian() {
        var tracker = RunQuantityTracker()
        for value in [5.0, 1, 5, 9] { tracker.add(value) }
        #expect(tracker.value(.median) == 5)
        for _ in 0..<RunQuantityTracker.capacity { tracker.add(7) }
        #expect(tracker.value(.median) == 7)
        tracker.add(1)
        #expect(tracker.value(.median) == 7)
        #expect(tracker.value(.minimum) == 1)
    }

    @Test("the median covers the last readings only; the average covers all")
    func capacity() {
        var tracker = RunQuantityTracker()
        for _ in 0..<RunQuantityTracker.capacity { tracker.add(1) }
        for _ in 0..<RunQuantityTracker.capacity { tracker.add(3) }
        #expect(tracker.value(.median) == 3)
        #expect(tracker.value(.average) == 2)
    }

    @Test("cadence is the steps over the last 20 seconds, once 5 seconds can be measured")
    func cadence() throws {
        var estimator = CadenceEstimator()
        #expect(estimator.add(totalSteps: 0, atElapsed: 0) == nil)
        #expect(estimator.add(totalSteps: 7, atElapsed: 4) == nil)
        // 14 steps in 5 seconds is 168 a minute.
        let first = estimator.add(totalSteps: 14, atElapsed: 5)
        #expect(first == 168)
        var later: Double?
        for second in 6...60 { later = estimator.add(totalSteps: Double(second) * 2.8, atElapsed: Double(second)) }
        #expect(abs(try #require(later) - 168) < 0.001)
    }

    @Test("a measure item survives encoding, and an unknown one is refused")
    func coding() throws {
        let item = RunScreenItem.measure(.groundContactTime, .median, .lastSplit)
        let data = try JSONEncoder().encode(item)
        #expect(try JSONDecoder().decode(RunScreenItem.self, from: data) == item)
        #expect(item.height == 1)
        #expect(!item.requiresSteps)
        let bad = Data(#"{"kind":"measure","id":"nothing.average"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RunScreenItem.self, from: bad) }
    }

    @Test("values are shown in the athlete's measure (decimals follow the region, so the test reads them with a point)")
    func display() {
        func shown(_ quantity: RunQuantity, _ value: Double, metric: Bool) -> String {
            let (number, unit) = quantity.display(value, metric: metric)
            return number.replacingOccurrences(of: ",", with: ".") + " " + unit
        }
        #expect(shown(.cadence, 172.4, metric: true) == "172 SPM")
        #expect(shown(.strideLength, 1.1, metric: true) == "1.10 M")
        #expect(shown(.strideLength, 1.0, metric: false) == "3.3 FT")
        #expect(shown(.runningSpeed, 3, metric: true) == "10.8 KM/H")
        #expect(shown(.verticalOscillation, 2.54, metric: false) == "1.0 IN")
    }
}

@Suite("SimulatedReadings (WATCH-135)")
struct SimulatedReadingsTests {
    @Test("every quantity but heart rate and pace (which come from the GPS) has a plausible, moving value")
    func values() {
        let first = SimulatedReadings.values(atElapsed: 0)
        let later = SimulatedReadings.values(atElapsed: 20)
        #expect(Set(first.keys) == Set(RunQuantity.allCases).subtracting([.heartRate, .pace]))
        for quantity in first.keys {
            #expect(first[quantity]! > 0)
            #expect(first[quantity] != later[quantity])
        }
        #expect((150...190).contains(first[.cadence]!))
    }
}

@Suite("RunStatisticsBook (WATCH-135)")
struct RunStatisticsBookTests {
    @Test("a new step makes the one before the last step, and its statistics start over")
    func steps() {
        var book = RunStatisticsBook()
        for value in [160.0, 170] { book.add(.cadence, value, stepKey: 0, splitKey: 0) }
        #expect(book.tracker(.cadence, .step)?.average == 165)
        #expect(book.tracker(.cadence, .lastStep) == nil)
        book.add(.cadence, 180, stepKey: 1, splitKey: 0)
        #expect(book.tracker(.cadence, .step)?.average == 180)
        #expect(book.tracker(.cadence, .lastStep)?.average == 165)
        #expect(book.tracker(.cadence, .lastStep)?.maximum == 170)
        #expect(book.tracker(.cadence, .run)?.average == 170)
    }

    @Test("advancing makes the step and split that went by the last ones even when nothing was read in between")
    func advance() {
        var book = RunStatisticsBook()
        book.add(.cadence, 170, stepKey: 0, splitKey: 0)
        book.advance(stepKey: 1, splitKey: 0)
        book.advance(stepKey: 2, splitKey: 1)
        #expect(book.tracker(.cadence, .lastStep) == nil)
        #expect(book.tracker(.cadence, .step) == nil)
        #expect(book.tracker(.cadence, .lastSplit)?.average == 170)
        // After the last step the step that was run is the last one, and no step is current.
        book.add(.cadence, 180, stepKey: 2, splitKey: 1)
        book.advance(stepKey: nil, splitKey: 1)
        #expect(book.tracker(.cadence, .lastStep)?.average == 180)
        #expect(book.tracker(.cadence, .step) == nil)
    }

    @Test("a new split does the same, with or without steps")
    func splits() {
        var book = RunStatisticsBook()
        book.add(.heartRate, 140, stepKey: nil, splitKey: 0)
        book.add(.heartRate, 150, stepKey: nil, splitKey: 0)
        book.add(.heartRate, 160, stepKey: nil, splitKey: 1)
        #expect(book.tracker(.heartRate, .lastSplit)?.average == 145)
        #expect(book.tracker(.heartRate, .split)?.average == 160)
        #expect(book.tracker(.heartRate, .step) == nil)
        // Another quantity in the same split joins it.
        book.add(.cadence, 170, stepKey: nil, splitKey: 1)
        #expect(book.tracker(.cadence, .split)?.current == 170)
        #expect(book.tracker(.cadence, .lastSplit) == nil)
    }

    @Test("the scopes of an item are written into its id, the whole run's left out for the old form")
    func scopeCoding() throws {
        let item = RunScreenItem.measure(.cadence, .average, .lastStep)
        #expect(item.requiresSteps)
        #expect(String(data: try JSONEncoder().encode(item), encoding: .utf8)!.contains("cadence.average.lastStep"))
        let old = Data(#"{"kind":"measure","id":"cadence.average"}"#.utf8)
        #expect(try JSONDecoder().decode(RunScreenItem.self, from: old) == .measure(.cadence, .average, .run))
        #expect(!RunScope.step.offers(.current))
        #expect(RunScope.run.offers(.current))
        #expect(!RunScreenItem.measure(.cadence, .average, .lastSplit).requiresSteps)
    }
}

@Suite("RunSpans and pace statistics (WATCH-135)")
struct RunSpanTests {
    private func mark(_ elapsed: Double, _ distance: Double, _ climb: Double = 0) -> RunSpans.Mark {
        RunSpans.Mark(elapsed: elapsed, distance: distance, climb: climb)
    }

    @Test("a split's time, distance and climb count from where it began, and the one before is kept")
    func splits() {
        var spans = RunSpans()
        spans.update(mark(0, 0), stepKey: nil, splitKey: 0)
        spans.update(mark(300, 1000, 12), stepKey: nil, splitKey: 1)
        #expect(spans.value(.time, .lastSplit, now: mark(300, 1000, 12)) == 300)
        #expect(spans.value(.climb, .lastSplit, now: mark(300, 1000, 12)) == 12)
        #expect(spans.value(.distance, .split, now: mark(400, 1350, 15)) == 350)
        #expect(spans.value(.time, .split, now: mark(400, 1350, 15)) == 100)
        #expect(spans.value(.time, .run, now: mark(400, 1350)) == nil)
        #expect(spans.value(.time, .step, now: mark(400, 1350)) == nil)
    }

    @Test("a step ending the workout leaves its figures as the last step")
    func steps() {
        var spans = RunSpans()
        spans.update(mark(0, 0), stepKey: 0, splitKey: 0)
        spans.update(mark(60, 200), stepKey: 1, splitKey: 0)
        spans.update(mark(180, 600), stepKey: nil, splitKey: 0)
        #expect(spans.value(.time, .lastStep, now: mark(200, 700)) == 120)
        #expect(spans.value(.distance, .lastStep, now: mark(200, 700)) == 400)
        #expect(spans.value(.time, .step, now: mark(200, 700)) == nil)
    }

    @Test("a pace is stored as a speed and shown as a pace, the lowest speed being the slowest")
    func pace() {
        func shown(_ speed: Double, metric: Bool) -> String {
            let (number, unit) = RunQuantity.pace.display(speed, metric: metric)
            return number + " " + unit
        }
        // 4 m/s is 250 s per km, 4:10.
        #expect(shown(4, metric: true) == "4'10\" /KM")
        #expect(shown(4, metric: false).hasSuffix("/MI"))
        #expect(RunStatistic.minimum.prefix(for: .pace) == "Slowest")
        #expect(RunStatistic.maximum.prefix(for: .pace) == "Fastest")
        #expect(RunStatistic.minimum.prefix(for: .cadence) == "Lowest")
        #expect(RunScreenItem.span(.time, .lastStep).requiresSteps)
        #expect(!RunScreenItem.span(.time, .split).requiresSteps)
        let item = RunScreenItem.span(.climb, .lastSplit)
        #expect((try? JSONDecoder().decode(RunScreenItem.self, from: JSONEncoder().encode(item))) == item)
    }
}
