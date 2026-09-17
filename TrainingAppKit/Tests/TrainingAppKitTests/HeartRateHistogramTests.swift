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

        let histogram = HeartRateHistogram.aggregating([activity], athlete: athlete, asOf: date(0))

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

        let histogram = HeartRateHistogram.aggregating([activity], athlete: athlete, asOf: date(0), binWidth: 5)

        // Average bpm 145 falls in the 145..<150 bin.
        let bin = try #require(histogram.bins.first { $0.bpm == 145 })
        #expect(bin.seconds == 30)
    }

    @Test("densifiedMinutes(domain:) zero-fills bins the histogram has no data for")
    func densifiedMinutesZeroFillsGaps() {
        let histogram = HeartRateHistogram(
            bins: [HeartRateHistogramBin(bpm: 110, seconds: 60)],
            binWidth: 5,
            zoneBoundariesBPM: nil
        )
        let points = histogram.densifiedMinutes(domain: 100...120)
        #expect(points.map(\.bpm) == [100, 105, 110, 115, 120])
        #expect(points.map(\.minutes) == [0, 0, 1, 0, 0])
    }

    @Test("densifiedMinutes(domain:) keeps real recorded time below zone 1, same as any other bin")
    func densifiedMinutesKeepsBelowZone1Data() {
        // Below zone 1 (recovery/warmup) at 90bpm -- unlike percentileBPM(_:), this shouldn't be
        // excluded: it's meaningful recorded time and stays visible on the chart.
        let histogram = HeartRateHistogram(
            bins: [HeartRateHistogramBin(bpm: 90, seconds: 120)],
            binWidth: 5,
            zoneBoundariesBPM: [100, 120, 140, 160, 175, 190]
        )
        let points = histogram.densifiedMinutes(domain: 85...100)
        #expect(points.first { $0.bpm == 90 }?.minutes == 2)
    }

    @Test("densifiedMinutes(domain:) excludes a bin whose grid position falls outside domain")
    func densifiedMinutesExcludesOutOfDomainBin() {
        // Regression test for MVP1-61: `domain`'s own edges don't fall on the binWidth grid (they're
        // offset from the athlete's zone boundaries), so the bin just below `domain.lowerBound` can
        // still get visited by the stride. Its real (nonzero) value must not leak into the result --
        // that's what previously made the histogram chart's curve look like it started rising before
        // its own x-axis did.
        let histogram = HeartRateHistogram(
            bins: [
                // This bin's own start (80) sits below domain.lowerBound (82), but the bin's range
                // (80..<85) still straddles it -- exactly the case that leaked through before.
                HeartRateHistogramBin(bpm: 80, seconds: 600),
                HeartRateHistogramBin(bpm: 85, seconds: 60),
            ],
            binWidth: 5,
            zoneBoundariesBPM: nil
        )
        let points = histogram.densifiedMinutes(domain: 82...90)
        #expect(points.map(\.bpm).allSatisfy { $0 >= 82 })
        #expect(points.first { $0.bpm == 80 } == nil)
    }

    @Test("densifiedMinutes(domain:) returns an empty result when no grid point falls inside domain")
    func densifiedMinutesEmptyForNarrowDomain() {
        // Bin-grid points sit at 100 and 105; a domain strictly between them (101...104) contains
        // neither, so both get filtered out just like the out-of-domain case above.
        let histogram = HeartRateHistogram(bins: [], binWidth: 5, zoneBoundariesBPM: nil)
        let points = histogram.densifiedMinutes(domain: 101...104)
        #expect(points.isEmpty)
    }

    @Test("minutesByZone() is nil when the athlete has no resolvable zone boundaries")
    func minutesByZoneNilWithoutBoundaries() {
        let histogram = HeartRateHistogram(
            bins: [HeartRateHistogramBin(bpm: 140, seconds: 60)], binWidth: 5, zoneBoundariesBPM: nil
        )
        #expect(histogram.minutesByZone() == nil)
    }

    @Test("minutesByZone() lists every zone, 0 minutes for zones with no recorded time")
    func minutesByZoneListsEveryZone() throws {
        let histogram = HeartRateHistogram(
            bins: [],
            binWidth: 5,
            zoneBoundariesBPM: [100, 120, 140, 160, 175, 190],
            timeInZone: TimeInZone(seconds: [1: 120])
        )
        let byZone = try #require(histogram.minutesByZone())
        #expect(byZone.map(\.zone) == HeartRateZone.allCases)
        #expect(byZone.first { $0.zone == .recovery }?.minutes == 2)
        #expect(byZone.filter { $0.zone != .recovery }.allSatisfy { $0.minutes == 0 })
    }

    @Test("minutesByZone() sums seconds from every zone recorded in timeInZone")
    func minutesByZoneSumsAllZones() throws {
        let histogram = HeartRateHistogram(
            bins: [],
            binWidth: 5,
            zoneBoundariesBPM: [100, 120, 140, 160, 175, 190],
            timeInZone: TimeInZone(seconds: [1: 180, 3: 120])
        )
        let byZone = try #require(histogram.minutesByZone())
        #expect(byZone.first { $0.zone == .recovery }?.minutes == 3)
        #expect(byZone.first { $0.zone == .tempo }?.minutes == 2)
        #expect(byZone.filter { $0.zone != .recovery && $0.zone != .tempo }.allSatisfy { $0.minutes == 0 })
    }

    @Test(
        """
        minutesByZone() credits each activity's own date-effective zone settings separately, \
        not one shared boundary for the whole week (MVP1-78 regression)
        """
    )
    func minutesByZoneUsesEachActivitysOwnDateEffectiveZones() throws {
        // Two 20-minute activities both held steady at 136bpm -- but (at a fixed 50bpm resting
        // heart rate) the athlete's zone2/zone3 boundary sits at ~137bpm on day 1 (136bpm still
        // zone 2) and ~135bpm on day 2 (136bpm now zone 3). The correct weekly total is 20 minutes
        // in zone 2 and 20 in zone 3, not 40 minutes bucketed under whichever boundary happens to
        // be the athlete's *current* one.
        let athlete = AthleteProfile(
            sex: .unspecified,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 300),
            timeZone: TimeZone(identifier: "UTC")!,
            weekStartsOn: .monday,
            heartRateZoneHistory: [
                HeartRateZoneSettings(effectiveDate: date(0), restingHeartRateBPM: 50, maxHeartRateBPM: 174),
                HeartRateZoneSettings(effectiveDate: date(86400), restingHeartRateBPM: 50, maxHeartRateBPM: 171),
            ]
        )
        func steadyActivity(start: Date) -> Activity {
            // Sampled every 30s (well under the 60s default gap threshold) so the full 20 minutes
            // integrates into one zone rather than being dropped as a gap.
            let sampleCount = 41
            let sampleInterval: TimeInterval = 30
            return Activity(
                source: .manual,
                sport: .running,
                start: start,
                duration: TimeInterval(sampleCount - 1) * sampleInterval,
                heartRate: (0..<sampleCount).map {
                    HeartRateSample(time: start.addingTimeInterval(Double($0) * sampleInterval), bpm: 136)
                }
            )
        }
        let day1Activity = steadyActivity(start: date(0))
        let day2Activity = steadyActivity(start: date(86400))

        let histogram = HeartRateHistogram.aggregating(
            [day1Activity, day2Activity], athlete: athlete, asOf: date(2 * 86400)
        )

        let byZone = try #require(histogram.minutesByZone())
        #expect(byZone.first { $0.zone == .aerobic }?.minutes == 20)
        #expect(byZone.first { $0.zone == .tempo }?.minutes == 20)
    }

    @Test("lowIntensityFraction is nil when the athlete has no resolvable zone boundaries")
    func lowIntensityFractionNilWithoutBoundaries() {
        let histogram = HeartRateHistogram(
            bins: [HeartRateHistogramBin(bpm: 140, seconds: 60)], binWidth: 5, zoneBoundariesBPM: nil
        )
        #expect(histogram.lowIntensityFraction == nil)
    }

    @Test("lowIntensityFraction is nil when no in-zone time was recorded")
    func lowIntensityFractionNilWhenEmpty() {
        let histogram = HeartRateHistogram(
            bins: [], binWidth: 5, zoneBoundariesBPM: [100, 120, 140, 160, 175, 190]
        )
        #expect(histogram.lowIntensityFraction == nil)
    }

    @Test("lowIntensityFraction is zones 1-2's share of zones 1-5's total, excluding zone 0 minutes")
    func lowIntensityFractionExcludesZoneZero() {
        // Zone 0 (below zone 1) gets 10 minutes -- deliberately the largest bucket here, so a
        // regression that folds it into either the numerator or denominator (the MVP1-76 bug this
        // property replaced `timeInZone.polarizedSplit.lowFraction` to fix) would visibly change
        // the expected 0.6 below.
        let histogram = HeartRateHistogram(
            bins: [],
            binWidth: 5,
            zoneBoundariesBPM: [100, 120, 140, 160, 175, 190],
            timeInZone: TimeInZone(seconds: [0: 600, 1: 180, 3: 120])
        )
        // Zone 1 (recovery): 3 minutes. Zone 3 (tempo): 2 minutes. Zones 2/4/5: 0. Low (zone 1-2)
        // is 3 of the zone-1-through-5 total of 5, i.e. 0.6 -- zone 0's 10 minutes count nowhere.
        #expect(histogram.lowIntensityFraction == 0.6)
    }

    @Test("aggregating(_:athlete:asOf:) reports zone boundaries in bpm when the athlete has zone settings")
    func aggregatingResolvesZoneBoundaries() throws {
        let athlete = AthleteProfile.fixture(
            timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 200
        )

        let histogram = HeartRateHistogram.aggregating([], athlete: athlete, asOf: date(0))

        let boundaries = try #require(histogram.zoneBoundariesBPM)
        #expect(boundaries.count == 6)
        // Zone 1's lower bound is the Karvonen 50% heart-rate-reserve point: 50 + 0.5*(200-50).
        #expect(boundaries.first == 125)
        // Zone 5's upper bound is 100% heart-rate reserve, i.e. max heart rate itself.
        #expect(boundaries.last == 200)
    }

    @Test(
        """
        aggregating(_:athlete:asOf:) resolves zone boundaries for the date passed in, not the \
        athlete's latest settings -- a week long in the past must shade against the zones actually \
        in effect that week, not whatever the athlete's zones are today (MVP1-78 follow-up)
        """
    )
    func aggregatingResolvesZoneBoundariesAsOfTheGivenDateNotTheLatest() throws {
        let athlete = AthleteProfile(
            sex: .unspecified,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 300),
            timeZone: TimeZone(identifier: "UTC")!,
            weekStartsOn: .monday,
            heartRateZoneHistory: [
                HeartRateZoneSettings(effectiveDate: date(0), restingHeartRateBPM: 50, maxHeartRateBPM: 200),
                // A much later "current" update -- well after the past week this test cares about.
                HeartRateZoneSettings(
                    effectiveDate: date(30 * 86400), restingHeartRateBPM: 55, maxHeartRateBPM: 210
                ),
            ]
        )

        let pastWeekHistogram = HeartRateHistogram.aggregating([], athlete: athlete, asOf: date(86400))
        let currentWeekHistogram = HeartRateHistogram.aggregating(
            [], athlete: athlete, asOf: date(31 * 86400)
        )

        let pastBoundaries = try #require(pastWeekHistogram.zoneBoundariesBPM)
        let currentBoundaries = try #require(currentWeekHistogram.zoneBoundariesBPM)
        // Karvonen 50% HRR point for the older settings: 50 + 0.5*(200-50).
        #expect(pastBoundaries.first == 125)
        // ...vs. 55 + 0.5*(210-55) for the newer ones -- proving `asOf`, not "always the athlete's
        // latest settings", drives which entry resolves.
        #expect(currentBoundaries.first == 132.5)
    }
}
