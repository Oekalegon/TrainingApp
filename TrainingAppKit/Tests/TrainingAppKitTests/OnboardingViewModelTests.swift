import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
private final class FakeProgress: OnboardingProgress {
    var hasCompletedOnboarding = false
    var hasDismissedHealthBanner = false
    var hasDismissedICloudBanner = false
}

@MainActor
private final class FakeICloud: ICloudAccountChecking {
    var status: ICloudAccountStatus
    init(_ status: ICloudAccountStatus) { self.status = status }
    func accountStatus() async -> ICloudAccountStatus { status }
}

@MainActor
@Suite("OnboardingViewModel", .serialized)
struct OnboardingViewModelTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_699_920_000 + Double(offset) * 86400)
    }

    private func makeStores() -> (InMemoryStore, StoreSet) {
        let store = InMemoryStore()
        return (store, StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        ))
    }

    private func makeModel() -> TrainingModel {
        TrainingModel(stores: makeStores().1, athlete: .fixture(timeZoneIdentifier: "UTC"))
    }

    // MARK: First-run introduction

    @Test("the introduction waits for the first load, then shows to a new install and not again once finished")
    func introductionLifecycle() {
        let progress = FakeProgress()
        let viewModel = OnboardingViewModel(model: makeModel(), progress: progress)
        #expect(!viewModel.showsOnboarding)

        viewModel.markLoaded()
        #expect(viewModel.showsOnboarding)

        viewModel.finish()
        #expect(!viewModel.showsOnboarding)
        #expect(progress.hasCompletedOnboarding)
    }

    @Test("an install that already connected Health never sees the introduction")
    func existingInstallSkipsIntroduction() async throws {
        let (store, stores) = makeStores()
        try await store.saveImportAnchor(ImportAnchor(data: Data([1])))
        let model = TrainingModel(stores: stores, athlete: .fixture(timeZoneIdentifier: "UTC"))
        try await model.load(in: day(0)...day(6), asOf: day(0))
        let viewModel = OnboardingViewModel(model: model, progress: FakeProgress())

        viewModel.markLoaded()

        #expect(!viewModel.showsOnboarding)
        #expect(viewModel.isHealthConnected)
    }

    @Test("a completed introduction stays gone on the next launch")
    func completedStaysCompleted() {
        let progress = FakeProgress()
        progress.hasCompletedOnboarding = true
        let viewModel = OnboardingViewModel(model: makeModel(), progress: progress)

        viewModel.markLoaded()

        #expect(!viewModel.showsOnboarding)
    }

    @Test("connecting runs the Health connection and records that it was asked, connected or not")
    func connectHealthRecordsAsk() async {
        let viewModel = OnboardingViewModel(model: makeModel(), progress: FakeProgress())
        var ran = false
        #expect(!viewModel.hasAskedForHealth)

        await viewModel.connectHealth { ran = true }

        #expect(ran)
        #expect(viewModel.hasAskedForHealth)
        #expect(!viewModel.isHealthConnected)  // nothing imported: the prompt may have been declined
    }

    // MARK: iCloud

    @Test("no account and a restricted account are unavailable; unknown and available aren't")
    func iCloudUnavailability() async {
        let checker = FakeICloud(.noAccount)
        let viewModel = OnboardingViewModel(model: makeModel(), progress: FakeProgress(), iCloud: checker)
        #expect(!viewModel.isICloudUnavailable)  // not checked yet

        await viewModel.refreshICloudStatus()
        #expect(viewModel.isICloudUnavailable)

        checker.status = .restricted
        await viewModel.refreshICloudStatus()
        #expect(viewModel.isICloudUnavailable)

        checker.status = .unknown
        await viewModel.refreshICloudStatus()
        #expect(!viewModel.isICloudUnavailable)

        checker.status = .available
        await viewModel.refreshICloudStatus()
        #expect(!viewModel.isICloudUnavailable)
    }

    @Test("the iCloud banner shows once the introduction is done, can be dismissed, and returns after iCloud worked again")
    func iCloudBannerLifecycle() async {
        let progress = FakeProgress()
        let checker = FakeICloud(.noAccount)
        let viewModel = OnboardingViewModel(model: makeModel(), progress: progress, iCloud: checker)
        viewModel.markLoaded()
        await viewModel.refreshICloudStatus()
        #expect(!viewModel.showsICloudBanner)  // the introduction is up and says it itself

        viewModel.finish()
        #expect(viewModel.showsICloudBanner)

        viewModel.dismissICloudBanner()
        #expect(!viewModel.showsICloudBanner)
        #expect(progress.hasDismissedICloudBanner)

        // Still failing on the next check: stays dismissed.
        await viewModel.refreshICloudStatus()
        #expect(!viewModel.showsICloudBanner)

        // Works again, then fails again: it's news again.
        checker.status = .available
        await viewModel.refreshICloudStatus()
        #expect(!progress.hasDismissedICloudBanner)
        checker.status = .noAccount
        await viewModel.refreshICloudStatus()
        #expect(viewModel.showsICloudBanner)
    }

    @Test("without a checker the status stays unknown and no banner shows")
    func noChecker() async {
        let viewModel = OnboardingViewModel(model: makeModel(), progress: FakeProgress())
        viewModel.markLoaded()
        viewModel.finish()

        await viewModel.refreshICloudStatus()

        #expect(viewModel.iCloudStatus == .unknown)
        #expect(!viewModel.showsICloudBanner)
    }

    // MARK: Health banner

    @Test("the Health banner needs the calendar showing, nothing imported and no dismissal")
    func healthBannerRules() {
        let progress = FakeProgress()
        progress.hasCompletedOnboarding = true
        let viewModel = OnboardingViewModel(model: makeModel(), progress: progress)
        viewModel.markLoaded()

        #expect(viewModel.showsHealthBanner(showsCalendar: true))
        #expect(!viewModel.showsHealthBanner(showsCalendar: false))  // the full empty state has its own button

        viewModel.dismissHealthBanner()
        #expect(!viewModel.showsHealthBanner(showsCalendar: true))
        #expect(progress.hasDismissedHealthBanner)
    }

    @Test("the Health banner waits for the introduction to be done")
    func healthBannerWaitsForIntroduction() {
        let viewModel = OnboardingViewModel(model: makeModel(), progress: FakeProgress())
        viewModel.markLoaded()
        #expect(!viewModel.showsHealthBanner(showsCalendar: true))

        viewModel.finish()
        #expect(viewModel.showsHealthBanner(showsCalendar: true))
    }

    // MARK: Week view model

    @Test("the week view model shows the Health banner once a plan is loaded and the introduction is done, and not before the first load")
    func weekViewModelHealthBanner() async throws {
        let progress = FakeProgress()
        progress.hasCompletedOnboarding = true
        let model = makeModel()
        let viewModel = WeekViewModel(
            model: model, refresher: StubRefresher(), onboardingProgress: progress, today: day(0)
        )
        #expect(!viewModel.showsConnectHealthBanner)

        await viewModel.load(asOf: day(0))
        #expect(viewModel.showsEmptyState)
        #expect(!viewModel.showsConnectHealthBanner)  // the full empty state is showing

        let workout = StructuredWorkout(
            name: "Easy", sport: .running, blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800))])]
        )
        try await model.add(workout, asOf: day(0))
        try await model.add(PlannedActivity(workoutID: workout.id, date: day(2)), asOf: day(0))
        #expect(viewModel.showsConnectHealthBanner)

        viewModel.onboarding.dismissHealthBanner()
        #expect(!viewModel.showsConnectHealthBanner)
    }

    // MARK: Stored progress

    @Test("UserDefaultsOnboardingProgress keeps each flag across instances")
    func userDefaultsProgress() throws {
        let suite = "OnboardingProgressTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UserDefaultsOnboardingProgress(defaults: defaults)
        #expect(!first.hasCompletedOnboarding && !first.hasDismissedHealthBanner && !first.hasDismissedICloudBanner)

        first.hasCompletedOnboarding = true
        first.hasDismissedICloudBanner = true

        let second = UserDefaultsOnboardingProgress(defaults: defaults)
        #expect(second.hasCompletedOnboarding)
        #expect(second.hasDismissedICloudBanner)
        #expect(!second.hasDismissedHealthBanner)
    }
}

@MainActor
private struct StubRefresher: ActivityRefreshing {
    func refreshActivities(asOf today: Date) async throws {}
    func resyncActivities(asOf today: Date) async throws {}
    func requestAuthorization() async throws {}
}
