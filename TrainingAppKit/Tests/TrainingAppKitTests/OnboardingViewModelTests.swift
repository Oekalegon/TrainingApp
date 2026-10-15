import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
private final class FakeProgress: OnboardingProgress {
    var hasCompletedOnboarding = false
    var hasDismissedHealthBanner = false
    var hasDismissedICloudBanner = false
    var hasDismissedDistanceBanner = false
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

    @Test("a Health connection that completes an import leaves the introduction up until Continue, with Health shown as connected")
    func introductionStaysAfterImport() async throws {
        let (store, stores) = makeStores()
        let model = TrainingModel(stores: stores, athlete: .fixture(timeZoneIdentifier: "UTC"))
        let progress = FakeProgress()
        let viewModel = OnboardingViewModel(model: model, progress: progress)
        viewModel.markLoaded()
        #expect(viewModel.showsOnboarding)

        // What connecting does: the import completes and the anchor is saved, whether or not access was granted.
        await viewModel.connectHealth {
            try? await store.saveImportAnchor(ImportAnchor(data: Data([1])))
            try? await model.load(in: day(0)...day(6), asOf: day(0))
        }

        #expect(viewModel.isHealthConnected)
        #expect(viewModel.hasAskedForHealth)
        #expect(viewModel.showsOnboarding)  // still up: Continue ends it

        viewModel.finish()
        #expect(!viewModel.showsOnboarding)
        #expect(progress.hasCompletedOnboarding)
    }

    @Test("a second connect while one is running is ignored")
    func connectIgnoresSecondTap() async {
        let viewModel = OnboardingViewModel(model: makeModel(), progress: FakeProgress())
        var runs = 0

        await viewModel.connectHealth {
            runs += 1
            // A tap landing while the first connection is still running.
            await viewModel.connectHealth { runs += 1 }
        }

        #expect(runs == 1)
        #expect(!viewModel.isConnecting)
    }

    @Test("the introduction is decided once: an import later in the session doesn't create it")
    func introductionDecidedOnce() async throws {
        let (store, stores) = makeStores()
        try await store.saveImportAnchor(ImportAnchor(data: Data([1])))
        let model = TrainingModel(stores: stores, athlete: .fixture(timeZoneIdentifier: "UTC"))
        try await model.load(in: day(0)...day(6), asOf: day(0))
        let viewModel = OnboardingViewModel(model: model, progress: FakeProgress())
        viewModel.markLoaded()
        #expect(!viewModel.showsOnboarding)

        viewModel.markLoaded()

        #expect(!viewModel.showsOnboarding)
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

    // MARK: Distance access (MVP2-146)

    @Test("the Allow distance banner needs Health connected, a type never asked about, and no dismissal")
    func distanceBannerRules() async throws {
        let (store, stores) = makeStores()
        try await store.saveImportAnchor(ImportAnchor(data: Data([1])))
        let model = TrainingModel(stores: stores, athlete: .fixture(timeZoneIdentifier: "UTC"))
        try await model.load(in: day(0)...day(6), asOf: day(0))
        let progress = FakeProgress()
        let viewModel = OnboardingViewModel(model: model, progress: progress)
        viewModel.markLoaded()
        #expect(!viewModel.showsDistanceBanner)  // nothing is unanswered yet

        viewModel.setHasUnansweredDistanceAccess(true)
        #expect(viewModel.showsDistanceBanner)

        viewModel.setHasUnansweredDistanceAccess(false)  // the athlete answered the Health sheet, either way
        #expect(!viewModel.showsDistanceBanner)

        viewModel.setHasUnansweredDistanceAccess(true)
        viewModel.dismissDistanceBanner()
        #expect(!viewModel.showsDistanceBanner)
        #expect(progress.hasDismissedDistanceBanner)
    }

    @Test("an install that never connected Health isn't asked about distance by a banner")
    func distanceBannerNeedsHealthConnected() {
        let viewModel = OnboardingViewModel(model: makeModel(), progress: FakeProgress())
        viewModel.markLoaded()
        viewModel.finish()

        viewModel.setHasUnansweredDistanceAccess(true)

        #expect(!viewModel.showsDistanceBanner)  // the Connect Health Data prompt covers it
    }

    @Test("allowing distance asks for access, then reads the workouts again, then checks what is still unanswered")
    func allowMoreHealthData() async throws {
        let (store, stores) = makeStores()
        try await store.saveImportAnchor(ImportAnchor(data: Data([1])))
        let model = TrainingModel(stores: stores, athlete: .fixture(timeZoneIdentifier: "UTC"))
        let refresher = RecordingRefresher(unanswered: true)
        let progress = FakeProgress()
        progress.hasCompletedOnboarding = true
        let viewModel = MicroCycleViewModel(model: model, refresher: refresher, onboardingProgress: progress, today: day(0))
        await viewModel.load(asOf: day(0))
        await viewModel.refreshHealthAccessStatus()
        #expect(viewModel.showsDistanceBanner)

        refresher.unanswered = false  // what Health reports once the sheet has been answered
        await viewModel.allowMoreHealthData(asOf: day(0))

        #expect(refresher.calls == ["unanswered", "authorize", "unanswered", "resync"])
        #expect(!viewModel.showsDistanceBanner)
    }

    @Test("only one banner shows at a time, the most important first, and dismissing it brings up the next")
    func oneBannerAtATime() async throws {
        let progress = FakeProgress()
        progress.hasCompletedOnboarding = true
        let model = makeModel()
        let viewModel = MicroCycleViewModel(
            model: model, refresher: StubRefresher(), onboardingProgress: progress, iCloud: FakeICloud(.noAccount), today: day(0)
        )
        await viewModel.load(asOf: day(0))
        await viewModel.onboarding.refreshICloudStatus()
        #expect(viewModel.bottomBanner == .iCloud)  // only iCloud applies: no plans, so the empty state is showing

        // A plan makes the calendar show, and with Health never connected, that banner outranks iCloud.
        let workout = StructuredWorkout(
            name: "Easy", sport: .running, blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800))])]
        )
        try await model.add(workout, asOf: day(0))
        try await model.add(PlannedActivity(workoutID: workout.id, date: day(2)), asOf: day(0))
        #expect(viewModel.bottomBanner == .connectHealth)

        viewModel.onboarding.dismissHealthBanner()
        #expect(viewModel.bottomBanner == .iCloud)

        viewModel.onboarding.dismissICloudBanner()
        #expect(viewModel.bottomBanner == nil)
    }

    @Test("with Health connected, the Allow distance banner outranks the iCloud one")
    func distanceOutranksICloud() async throws {
        let (store, stores) = makeStores()
        try await store.saveImportAnchor(ImportAnchor(data: Data([1])))
        let model = TrainingModel(stores: stores, athlete: .fixture(timeZoneIdentifier: "UTC"))
        let progress = FakeProgress()
        progress.hasCompletedOnboarding = true
        let viewModel = MicroCycleViewModel(
            model: model, refresher: RecordingRefresher(unanswered: true), onboardingProgress: progress,
            iCloud: FakeICloud(.noAccount), today: day(0)
        )
        await viewModel.load(asOf: day(0))
        await viewModel.onboarding.refreshICloudStatus()
        await viewModel.refreshHealthAccessStatus()

        #expect(viewModel.bottomBanner == .allowDistance)

        viewModel.onboarding.dismissDistanceBanner()
        #expect(viewModel.bottomBanner == .iCloud)
    }

    @Test("a second tap on Allow Distance while the first is still asking or re-reading is ignored")
    func allowMoreHealthDataIgnoresSecondTap() async throws {
        let (store, stores) = makeStores()
        try await store.saveImportAnchor(ImportAnchor(data: Data([1])))
        let model = TrainingModel(stores: stores, athlete: .fixture(timeZoneIdentifier: "UTC"))
        let refresher = RecordingRefresher(unanswered: true)
        let progress = FakeProgress()
        progress.hasCompletedOnboarding = true
        let viewModel = MicroCycleViewModel(model: model, refresher: refresher, onboardingProgress: progress, today: day(0))
        await viewModel.load(asOf: day(0))
        // A tap landing while the Health sheet is still up.
        refresher.whileAuthorizing = { await viewModel.allowMoreHealthData(asOf: self.day(0)) }

        await viewModel.allowMoreHealthData(asOf: day(0))

        #expect(refresher.calls.filter { $0 == "authorize" }.count == 1)
        #expect(refresher.calls.filter { $0 == "resync" }.count == 1)
        #expect(!viewModel.isAllowingHealthData)
    }

    // MARK: Week view model

    @Test("the week view model shows the Health banner once a plan is loaded and the introduction is done, and not before the first load")
    func microCycleViewModelHealthBanner() async throws {
        let progress = FakeProgress()
        progress.hasCompletedOnboarding = true
        let model = makeModel()
        let viewModel = MicroCycleViewModel(
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

    @Test("a failed first load doesn't count as loaded, so the introduction doesn't guess")
    func failedFirstLoadIsNotLoaded() async {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: UnreadablePlanStore(base: store), workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: .fixture(timeZoneIdentifier: "UTC"))
        let viewModel = MicroCycleViewModel(model: model, refresher: StubRefresher(), onboardingProgress: FakeProgress(), today: day(0))

        await viewModel.load(asOf: day(0))

        #expect(!viewModel.onboarding.isLoaded)
        #expect(!viewModel.onboarding.showsOnboarding)
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
        first.hasDismissedDistanceBanner = true

        let second = UserDefaultsOnboardingProgress(defaults: defaults)
        #expect(second.hasCompletedOnboarding)
        #expect(second.hasDismissedICloudBanner)
        #expect(second.hasDismissedDistanceBanner)
        #expect(!second.hasDismissedHealthBanner)
    }
}

@MainActor
private struct StubRefresher: ActivityRefreshing {
    func refreshActivities(asOf today: Date) async throws {}
    func resyncActivities(asOf today: Date) async throws {}
    func requestAuthorization() async throws {}
}

/// A plan store whose reads fail, so the model's first load fails.
private struct UnreadablePlanStore: PlanStore {
    struct Failure: Error {}
    let base: InMemoryStore

    func plans(in range: ClosedRange<Date>) async throws -> [PlannedActivity] { throw Failure() }
    func upsert(_ plans: [PlannedActivity]) async throws { try await base.upsert(plans) }
    func plan(id: UUID) async throws -> PlannedActivity? { try await base.plan(id: id) }
    func deletePlan(id: UUID) async throws { try await base.deletePlan(id: id) }
}

/// A refresher that records what it was asked, and answers `hasUnansweredDistanceAccess()`.
@MainActor
private final class RecordingRefresher: ActivityRefreshing {
    var unanswered: Bool
    private(set) var calls: [String] = []

    init(unanswered: Bool) { self.unanswered = unanswered }

    func refreshActivities(asOf today: Date) async throws { calls.append("refresh") }
    func resyncActivities(asOf today: Date) async throws { calls.append("resync") }
    /// Runs while "asking", to simulate a second tap during the Health sheet.
    var whileAuthorizing: (() async -> Void)?

    func requestAuthorization() async throws {
        calls.append("authorize")
        await whileAuthorizing?()
    }
    func hasUnansweredDistanceAccess() async -> Bool {
        calls.append("unanswered")
        return unanswered
    }
}
