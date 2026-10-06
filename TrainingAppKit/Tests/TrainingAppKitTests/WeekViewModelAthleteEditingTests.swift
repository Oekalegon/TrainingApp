import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// MVP2-132: the athlete edits their profile from the Athlete tab.
@MainActor
@Suite("WeekViewModel athlete editing")
struct WeekViewModelAthleteEditingTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func day(_ offset: Int) -> Date {
        now.addingTimeInterval(Double(offset) * 86400)
    }

    private func makeViewModel(
        athlete: AthleteProfile = AthleteProfile.fixture(timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190),
        refresher: any ActivityRefreshing = FakeRefresher()
    ) -> (WeekViewModel, TrainingModel, InMemoryStore) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: athlete)
        return (WeekViewModel(model: model, refresher: refresher, today: now), model, store)
    }

    @Test("renaming trims the name, saves it, and an empty name is allowed")
    func renaming() async throws {
        let (viewModel, model, store) = makeViewModel()

        #expect(await viewModel.setAthleteName("  Alex Athlete \n", asOf: now))

        #expect(model.athlete.name == "Alex Athlete")
        #expect(try await store.athleteProfile()?.name == "Alex Athlete")
        #expect(await viewModel.setAthleteName("   ", asOf: now))
        #expect(viewModel.athleteViewModel.displayName == "Athlete")
    }

    @Test("the avatar is saved with the profile and can be removed")
    func avatar() async throws {
        let (viewModel, model, store) = makeViewModel()

        #expect(await viewModel.setAthleteAvatar(Data([9, 9]), asOf: now))
        #expect(model.athlete.avatarImageData == Data([9, 9]))
        #expect(try await store.athleteProfile()?.avatarImageData == Data([9, 9]))

        #expect(await viewModel.setAthleteAvatar(nil, asOf: now))
        #expect(model.athlete.avatarImageData == nil)
    }

    @Test("heart-rate settings recorded from a date are saved, replace that day's entry, and can be removed")
    func heartRateSettingsLifecycle() async throws {
        let (viewModel, model, store) = makeViewModel()
        let first = HeartRateZoneSettings(
            effectiveDate: day(2), restingHeartRateBPM: 46, maxHeartRateBPM: 186, maxHeartRateSource: .manual
        )

        #expect(await viewModel.recordHeartRateSettings(first, asOf: now))
        #expect(model.athlete.heartRateZoneHistory.count == 2)

        var again = first
        again.maxHeartRateBPM = 188
        #expect(await viewModel.recordHeartRateSettings(again, asOf: now))
        #expect(model.athlete.heartRateZoneHistory.count == 2)
        #expect(try await store.athleteProfile()?.currentHeartRateZoneSettings?.maxHeartRateBPM == 188)

        #expect(await viewModel.removeHeartRateSettings(on: day(2), asOf: now))
        #expect(model.athlete.heartRateZoneHistory.count == 1)
        // The last entry stays.
        #expect(await viewModel.removeHeartRateSettings(on: .distantPast, asOf: now))
        #expect(model.athlete.heartRateZoneHistory.count == 1)
    }

    @Test("a recorded threshold pace is dated and keeps the zone multipliers")
    func thresholdPace() async {
        let (viewModel, model, _) = makeViewModel()
        let multipliers = model.athlete.paceModel.zonePaceMultipliers

        #expect(await viewModel.recordThresholdPace(secondsPerKilometer: 270, from: day(1), asOf: now))

        #expect(model.athlete.paceModel.thresholdPaceSecondsPerKilometer == 270)
        #expect(model.athlete.paceModel.zonePaceMultipliers == multipliers)
        #expect(model.athlete.paceModel(asOf: day(0)).thresholdPaceSecondsPerKilometer == 300)
        #expect(model.athlete.paceHistory.count == 2)

        #expect(await viewModel.removePaceSettings(on: day(1), asOf: now))
        #expect(model.athlete.paceModel.thresholdPaceSecondsPerKilometer == 300)
    }

    @Test("turning the Apple Health resting-HR switch on imports right away; turning it off doesn't")
    func healthKitSwitch() async {
        let refresher = FakeRefresher()
        let (viewModel, model, _) = makeViewModel(refresher: refresher)

        #expect(await viewModel.setUsesHealthKitRestingHeartRate(false, asOf: now))
        #expect(!model.athlete.usesHealthKitRestingHeartRate)
        #expect(refresher.callCount == 0)

        #expect(await viewModel.setUsesHealthKitRestingHeartRate(true, asOf: now))
        #expect(model.athlete.usesHealthKitRestingHeartRate)
        #expect(refresher.callCount == 1)
    }

    @Test("changing the week start moves the week grouping and keeps the displayed day in view")
    func weekStartChange() async {
        let (viewModel, model, _) = makeViewModel(
            athlete: AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        )
        await viewModel.load(asOf: now)
        let before = viewModel.displayedWeekStart
        let calendarBefore = viewModel.athleteCalendar
        #expect(calendarBefore.component(.weekday, from: before) == Weekday.monday.rawValue)

        #expect(await viewModel.setWeekStartsOn(.sunday, asOf: now))

        #expect(model.athlete.weekStartsOn == .sunday)
        #expect(viewModel.athleteCalendar.firstWeekday == Weekday.sunday.rawValue)
        #expect(viewModel.athleteCalendar.component(.weekday, from: viewModel.displayedWeekStart) == Weekday.sunday.rawValue)
        // The new week still contains the day the old one started on.
        #expect(viewModel.weekDates.contains { viewModel.athleteCalendar.isDate($0, inSameDayAs: before) })
    }

    @Test("changing the time zone regroups the days: the calendar, the week start and the athlete's zone all follow")
    func timeZoneChange() async throws {
        let (viewModel, model, store) = makeViewModel()
        await viewModel.load(asOf: now)
        let auckland = try #require(TimeZone(identifier: "Pacific/Auckland"))

        #expect(await viewModel.setTimeZone(auckland, asOf: now))

        #expect(model.athlete.timeZone == auckland)
        #expect(viewModel.athleteTimeZone == auckland)
        #expect(viewModel.athleteCalendar.timeZone == auckland)
        #expect(viewModel.athleteCalendar.startOfDay(for: viewModel.displayedWeekStart) == viewModel.displayedWeekStart)
        #expect(try await store.athleteProfile()?.timeZone == auckland)
    }

    @Test("an activity moves to another day when the time zone changes")
    func activityRegroupsWithTimeZone() async throws {
        let (_, model, store) = makeViewModel()
        // 23:30 UTC: still that day in UTC, already the next day in Auckland (UTC+12/13).
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let evening = utc.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 23, minute: 30))!
        let activity = Activity(source: .manual, sport: .running, start: evening, duration: 1800, perceivedExertion: 4)
        try await store.upsert([activity])
        let viewModelNow = evening
        let freshViewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: viewModelNow)
        await freshViewModel.load(asOf: viewModelNow)
        #expect(freshViewModel.activities(on: evening).count == 1)
        let auckland = try #require(TimeZone(identifier: "Pacific/Auckland"))

        #expect(await freshViewModel.setTimeZone(auckland, asOf: viewModelNow))

        let nextDayInAuckland = evening.addingTimeInterval(3600)
        #expect(freshViewModel.activities(on: nextDayInAuckland).count == 1)
        #expect(freshViewModel.activities(on: evening.addingTimeInterval(-86400)).isEmpty)
    }

    @Test("a failed save changes nothing and says so")
    func failedSave() async {
        let store = InMemoryStore()
        let failing = FailingAthleteStore(base: store)
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: failing
        )
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture(timeZoneIdentifier: "UTC"))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: now)
        await failing.setFailsSaves(true)
        let before = model.athlete

        #expect(await viewModel.setAthleteName("Alex", asOf: now) == false)
        #expect(await viewModel.setWeekStartsOn(.saturday, asOf: now) == false)

        #expect(model.athlete == before)
        #expect(viewModel.athleteCalendar.firstWeekday == Weekday.monday.rawValue)
    }
}
