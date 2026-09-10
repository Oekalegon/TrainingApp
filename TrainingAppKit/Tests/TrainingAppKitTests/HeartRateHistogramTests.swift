import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@Suite("HeartRateHistogram")
struct HeartRateHistogramTests {
    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offset)
    }

    @Test("percentileBPM(_:) is nil when the histogram has no time recorded")
    func percentileBPMNilWhenEmpty() {
        let histogram = HeartRateHistogram(bins: [], binWidth: 5, zoneBoundariesBPM: nil)
        #expect(histogram.percentileBPM(0.8) == nil)
    }

    @Test("percentileBPM(_:) interpolates within the bin where cumulative time crosses the target fraction")
    func percentileBPMInterpolatesWithinBin() {
        // 80 minutes at 100bpm, 20 minutes at 150bpm -- 100 total, so the 80th percentile sits
        // exactly at the boundary between the two bins: every second up to and including the
        // 100bpm bin's own is needed to reach 80% of the total, landing right at 105 (100 + binWidth).
        let histogram = HeartRateHistogram(
            bins: [
                HeartRateHistogramBin(bpm: 100, seconds: 80 * 60),
                HeartRateHistogramBin(bpm: 150, seconds: 20 * 60),
            ],
            binWidth: 5,
            zoneBoundariesBPM: nil
        )
        #expect(histogram.percentileBPM(0.8) == 105)
    }

    @Test("percentileBPM(_:) finds the midpoint when the target fraction lands halfway through a bin")
    func percentileBPMHalfwayThroughBin() {
        // 100 minutes total, all in one 5-wide bin -- the 50th percentile should land halfway
        // across that bin's own width.
        let histogram = HeartRateHistogram(
            bins: [HeartRateHistogramBin(bpm: 140, seconds: 100 * 60)],
            binWidth: 5,
            zoneBoundariesBPM: nil
        )
        #expect(histogram.percentileBPM(0.5) == 142.5)
    }

    @Test("percentileBPM(_:) excludes time below zone 1's lower bound, but not time above zone 5's upper bound")
    func percentileBPMExcludesBelowZone1() {
        let histogram = HeartRateHistogram(
            bins: [
                // Below zone 1 (recovery/warmup) -- shouldn't count toward the total at all.
                HeartRateHistogramBin(bpm: 80, seconds: 1000 * 60),
                HeartRateHistogramBin(bpm: 100, seconds: 80 * 60),
                // Above zone 5's upper bound (190) -- still counts, same as any other in-zone bin.
                HeartRateHistogramBin(bpm: 195, seconds: 20 * 60),
            ],
            binWidth: 5,
            zoneBoundariesBPM: [100, 120, 140, 160, 175, 190]
        )
        // Of the in-zone 100 minutes (80 at 100bpm, 20 at 195bpm), the 80th percentile lands right
        // at the boundary between the two -- same shape as `percentileBPMInterpolatesWithinBin`,
        // just with the below-zone-1 bin (which would otherwise dominate the total) excluded.
        #expect(histogram.percentileBPM(0.8) == 105)
    }

    @Test("aggregating(_:athlete:) skips gaps longer than gapThresholdSeconds")
    func aggregatingSkipsLongGaps() {
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let activity = Activity(
            source: .manual,
            sport: .running,
            start: date(0),
            duration: 700,
            heartRate: [
                HeartRateSample(time: date(0), bpm: 140),
                HeartRateSample(time: date(30), bpm: 142),
                // A 600s gap -- well past the 60s default threshold -- leaves this last sample
                // without a forming pair on either side, so it contributes no segment at all.
                HeartRateSample(time: date(630), bpm: 160),
            ]
        )

        let histogram = HeartRateHistogram.aggregating([activity], athlete: athlete)

        #expect(histogram.bins.reduce(0) { $0 + $1.seconds } == 30)
        #expect(histogram.bins.allSatisfy { $0.bpm < 150 })
    }

    @Test("aggregating(_:athlete:) bins by the average of each consecutive sample pair")
    func aggregatingBinsByAverageBPM() throws {
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let activity = Activity(
            source: .manual,
            sport: .running,
            start: date(0),
            duration: 30,
            heartRate: [
                HeartRateSample(time: date(0), bpm: 140),
                HeartRateSample(time: date(30), bpm: 150),
            ]
        )

        let histogram = HeartRateHistogram.aggregating([activity], athlete: athlete, binWidth: 5)

        // Average bpm 145 falls in the 145..<150 bin.
        let bin = try #require(histogram.bins.first { $0.bpm == 145 })
        #expect(bin.seconds == 30)
    }

    @Test("aggregating(_:athlete:) reports zone boundaries in bpm when the athlete has zone settings")
    func aggregatingResolvesZoneBoundaries() throws {
        let athlete = AthleteProfile.fixture(
            timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 200
        )

        let histogram = HeartRateHistogram.aggregating([], athlete: athlete)

        let boundaries = try #require(histogram.zoneBoundariesBPM)
        #expect(boundaries.count == 6)
        // Zone 1's lower bound is the Karvonen 50% heart-rate-reserve point: 50 + 0.5*(200-50).
        #expect(boundaries.first == 125)
        // Zone 5's upper bound is 100% heart-rate reserve, i.e. max heart rate itself.
        #expect(boundaries.last == 200)
    }
}
