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
        let item = RunScreenItem.measure(.groundContactTime, .median)
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
    @Test("every quantity but heart rate has a plausible, moving value")
    func values() {
        let first = SimulatedReadings.values(atElapsed: 0)
        let later = SimulatedReadings.values(atElapsed: 20)
        #expect(Set(first.keys) == Set(RunQuantity.allCases).subtracting([.heartRate]))
        for quantity in first.keys {
            #expect(first[quantity]! > 0)
            #expect(first[quantity] != later[quantity])
        }
        #expect((150...190).contains(first[.cadence]!))
    }
}
