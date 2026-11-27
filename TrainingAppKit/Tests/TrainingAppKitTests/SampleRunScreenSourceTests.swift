import Foundation
import Testing
import TrainingWatchKit
@testable import TrainingAppKit

@MainActor
@Suite("SampleRunScreenSource and the preview (WATCH-138)")
struct SampleRunScreenSourceTests {
    @Test("a planned workout's sample has a step with a pace target, and every statistic of every scope has a value")
    func workoutSample() throws {
        let source = SampleRunScreenSource(isWorkout: true)
        let now = Date.now
        let current = try #require(source.stepEngine?.current)
        #expect(current.step.kind == .work)
        #expect(StepPaceTarget(step: current.step) != nil)
        #expect(source.stepProgress(at: now) != nil)
        for quantity in RunQuantity.allCases {
            for scope in RunScope.allCases {
                for statistic in RunStatistic.allCases where scope.offers(statistic) {
                    #expect(source.reading(quantity, statistic, scope, at: now) != nil, "\(quantity) \(statistic) \(scope)")
                }
            }
        }
        let mark = source.spanMark(at: now)
        for kind in RunSpanKind.allCases {
            for scope in [RunScope.step, .lastStep, .split, .lastSplit] {
                #expect(source.spans.value(kind, scope, now: mark) != nil, "\(kind) \(scope)")
            }
        }
    }

    @Test("a free run's sample has no steps, but the splits and the run's own readings")
    func freeSample() {
        let source = SampleRunScreenSource(isWorkout: false)
        let now = Date.now
        #expect(source.stepEngine == nil)
        #expect(source.stepProgress(at: now) == nil)
        #expect(source.reading(.cadence, .average, .split, at: now) != nil)
        #expect(source.reading(.cadence, .average, .step, at: now) == nil)
    }

    @Test("the run's figures are there for the older metrics and the widgets")
    func figures() {
        let source = SampleRunScreenSource(isWorkout: true)
        #expect(source.stats.altitude != nil && source.stats.grade != nil)
        #expect(source.stats.averageHeartRate != nil && source.stats.maxHeartRate != nil)
        #expect(source.stats.elevationGain > 0)
        #expect(source.zoneBands != nil)
        #expect(source.zoneTimeFractions?.count == 6)
        #expect(source.elapsed(at: .now) == SampleRunScreenSource.sampleElapsed)
        #expect(source.battery(at: .now).level != nil)
        #expect(source.averageSecondsPerMeter != nil)
    }

    @Test("a smaller watch fits one unit fewer than the largest")
    func watches() {
        #expect(PreviewWatch.large.fittingUnits == RunScreen.capacity)
        #expect(PreviewWatch.small.fittingUnits == RunScreen.capacity - 1)
        #expect(PreviewWatch.allCases.count == 2)
    }

    @Test("each watch has its own screen, the units it fits come from the watch's own rule, and only the Ultra has the Action button and a crown guard (WATCH-142)")
    func eachWatchHasItsOwnDrawing() {
        let ultra = PreviewWatch.large
        let other = PreviewWatch.small
        #expect(ultra.screenSize == CGSize(width: 205, height: 251))
        #expect(other.screenSize.width < ultra.screenSize.width && other.screenSize.height < ultra.screenSize.height)
        for watch in PreviewWatch.allCases {
            #expect(watch.fittingUnits == RunScreenPage.fittingUnits(forScreenHeight: watch.screenSize.height))
            #expect(watch.screenCornerRadius < watch.caseCornerRadius)
        }
        #expect(ultra.hasActionButton && ultra.hasCrownGuard)
        #expect(!other.hasActionButton && !other.hasCrownGuard)
        // The Ultra's case is the squarer one, relative to its size.
        #expect(ultra.caseCornerRadius / ultra.screenSize.width < other.caseCornerRadius / other.screenSize.width)
    }
}
