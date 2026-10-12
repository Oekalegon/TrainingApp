import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@Suite("ActivityDetailViewModel")
struct ActivityDetailViewModelTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    @Test("falls back to duration/RPE load when there's no heart-rate data")
    func fallsBackToDurationRPEWithoutHeartRate() {
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "Europe/Amsterdam")
        let activity = Activity(
            source: .manual, sport: .strength, start: day(0), duration: 1800,
            perceivedExertion: 6
        )

        let viewModel = ActivityDetailViewModel(activity: activity, athlete: athlete)

        #expect(viewModel.summary.load.confidence > 0)
        #expect(viewModel.summary.load.method == .durationRPE)
        #expect(viewModel.summary.timeInZone.total == 0)
        #expect(viewModel.summary.averageHeartRateBPM == nil)
        #expect(viewModel.timeZone.identifier == "Europe/Amsterdam")
    }

    @Test("computes time in zone and average heart rate from heart-rate samples")
    func computesTimeInZoneFromHeartRateSamples() {
        let athlete = AthleteProfile.fixture(
            timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190
        )
        let start = day(0)
        // Samples 30s apart (well under the 60s gap threshold), so the whole 10 minutes forms one
        // continuous segment instead of being excluded as a pause.
        let samples = stride(from: 0, through: 600, by: 30).map {
            HeartRateSample(time: start.addingTimeInterval(TimeInterval($0)), bpm: 175)
        }
        let activity = Activity(
            source: .manual, sport: .running, start: start, duration: 600,
            heartRate: samples
        )

        let viewModel = ActivityDetailViewModel(activity: activity, athlete: athlete)

        #expect(viewModel.summary.load.confidence > 0)
        #expect(viewModel.summary.load.method == .exponentialTRIMP)
        #expect(viewModel.summary.timeInZone.total > 0)
        #expect(viewModel.summary.averageHeartRateBPM == 175)
    }

    @Test("reports zero confidence when neither calculator can score the activity")
    func reportsZeroConfidenceWhenUnscorable() {
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let activity = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)

        let viewModel = ActivityDetailViewModel(activity: activity, athlete: athlete)

        #expect(viewModel.summary.load.confidence == 0)
    }

    @Test("offers the plan's sport and venue only when the activity differs from them (MVP2-151)")
    func differsFromPlan() {
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let plan = StructuredWorkout(name: "Easy", sport: .running, venue: .indoor(.treadmill), blocks: [])
        let outdoors = Activity(source: .manual, sport: .running, venue: .outdoor(nil), start: day(0), duration: 1800)
        let treadmill = Activity(source: .manual, sport: .running, venue: .indoor(.treadmill), start: day(0), duration: 1800)

        #expect(ActivityDetailViewModel(activity: outdoors, athlete: athlete, planWorkout: plan).differsFromPlan)
        #expect(!ActivityDetailViewModel(activity: treadmill, athlete: athlete, planWorkout: plan).differsFromPlan)
        #expect(!ActivityDetailViewModel(activity: outdoors, athlete: athlete).differsFromPlan)
    }
}
