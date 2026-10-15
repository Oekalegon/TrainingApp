import Foundation
import TrainingCore

/// The first-run introduction and the permission banners (MVP2-147, design doc §2.1a).
///
/// Health and iCloud are explained once, on first launch, by an introduction the athlete can leave at
/// any step. Neither answer is required: skipping Health leaves the empty state (or, once plans exist,
/// a "Connect Health Data" banner), and no iCloud account leaves a warning banner; the app works
/// either way.
///
/// What can be known is deliberately small. HealthKit doesn't say whether read access was granted,
/// only that the prompt was shown, and never tells the app when access is later turned off, so
/// "connected" here means a Health import has completed (`TrainingModel.hasEverImportedActivities`)
/// and a revocation isn't detected: the Apple Health row says where to turn access back on. iCloud,
/// unlike Health, can be asked.
@Observable
@MainActor
public final class OnboardingViewModel {
    private let model: TrainingModel
    private let progress: any OnboardingProgress
    private let iCloud: (any ICloudAccountChecking)?

    /// The iCloud account's status as last checked; ``ICloudAccountStatus/unknown`` until
    /// ``refreshICloudStatus()`` has run, or without a checker.
    public private(set) var iCloudStatus: ICloudAccountStatus = .unknown
    /// `true` once the athlete has passed the Health step in this introduction, connecting or not, so
    /// the screen can say what happened.
    public private(set) var hasAskedForHealth = false
    /// Whether the week's first load has finished: until then `hasEverImportedActivities` can't be
    /// trusted, and an athlete who already connected would see the introduction flash up.
    private(set) var isLoaded = false
    /// Whether this launch shows the introduction, decided once when the first load finishes. Not
    /// re-derived while it is up: connecting Health flips `hasEverImportedActivities` (even when
    /// access was denied, since the import still completes), and the introduction must stay to show
    /// the result and the iCloud step until the athlete taps Continue.
    private var needsOnboarding = false
    /// Set before the first `await` of ``connectHealth(_:)``, so a second tap in the same moment
    /// can't start a second connection.
    public private(set) var isConnecting = false
    // Mirrors of `progress`, kept here so the views update when they change: the stored record
    // (`UserDefaults`) isn't observable.
    private var hasCompletedOnboarding: Bool
    private var hasDismissedHealthBanner: Bool
    private var hasDismissedICloudBanner: Bool
    private var hasDismissedDistanceBanner: Bool
    /// Whether the athlete was never asked to allow distance, as last checked (MVP2-146).
    public private(set) var hasUnansweredDistanceAccess = false

    /// - Parameters:
    ///   - model: The training model; says whether Health has ever been imported.
    ///   - progress: What the athlete has already dismissed.
    ///   - iCloud: Looks up the iCloud account; `nil` (previews, tests) leaves the status unknown.
    public init(model: TrainingModel, progress: any OnboardingProgress, iCloud: (any ICloudAccountChecking)? = nil) {
        self.model = model
        self.progress = progress
        self.iCloud = iCloud
        hasCompletedOnboarding = progress.hasCompletedOnboarding
        hasDismissedHealthBanner = progress.hasDismissedHealthBanner
        hasDismissedICloudBanner = progress.hasDismissedICloudBanner
        hasDismissedDistanceBanner = progress.hasDismissedDistanceBanner
    }

    /// Tells the view model the first load has finished (see `MicroCycleViewModel.load(asOf:)`).
    func markLoaded() {
        guard !isLoaded else { return }
        isLoaded = true
        needsOnboarding = !hasCompletedOnboarding && !model.hasEverImportedActivities
    }

    /// Whether the first-run introduction is up: from the first load until the athlete leaves it, and
    /// never for an athlete who has completed it or already connected Health (an existing install).
    public var showsOnboarding: Bool {
        needsOnboarding && !hasCompletedOnboarding
    }

    /// Whether Health has been connected: an import has completed.
    public var isHealthConnected: Bool {
        model.hasEverImportedActivities
    }

    /// Records that the athlete went through the Health step, whether or not it connected.
    ///
    /// - Parameter connect: Runs the Health connection (`MicroCycleViewModel.connectHealthData(asOf:)`).
    public func connectHealth(_ connect: () async -> Void) async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        await connect()
        hasAskedForHealth = true
    }

    /// Leaves the introduction for good: continuing and skipping both end it.
    public func finish() {
        hasCompletedOnboarding = true
        progress.hasCompletedOnboarding = true
    }

    /// Looks up the iCloud account again, e.g. when the app becomes active after the athlete signed
    /// in under Settings.
    public func refreshICloudStatus() async {
        guard let iCloud else { return }
        iCloudStatus = await iCloud.accountStatus()
        // Working again: a later failure is news again, so a dismissal of the earlier one is forgotten.
        if iCloudStatus == .available, hasDismissedICloudBanner {
            hasDismissedICloudBanner = false
            progress.hasDismissedICloudBanner = false
        }
    }

    /// Whether iCloud is known to be unusable: signed out or restricted. Not for ``unknown``, so a
    /// momentary failure doesn't raise a warning.
    public var isICloudUnavailable: Bool {
        iCloudStatus == .noAccount || iCloudStatus == .restricted
    }

    /// Whether the week view shows the "Connect Health Data" banner: nothing imported, not dismissed,
    /// and the calendar is showing. Without plans the full empty state is shown instead, which has
    /// its own "Connect Health Data" button.
    ///
    /// - Parameter showsCalendar: Whether the week view is showing the calendar, not the empty state
    ///   (`!MicroCycleViewModel.showsEmptyState`).
    public func showsHealthBanner(showsCalendar: Bool) -> Bool {
        showsCalendar && !model.hasEverImportedActivities && !hasDismissedHealthBanner && !showsOnboarding
    }

    /// Hides the Health banner for good.
    public func dismissHealthBanner() {
        hasDismissedHealthBanner = true
        progress.hasDismissedHealthBanner = true
    }

    /// Whether the week view shows the "iCloud isn't available" banner: iCloud is known to be
    /// unusable, it wasn't dismissed, and the introduction isn't up.
    public var showsICloudBanner: Bool {
        isICloudUnavailable && !hasDismissedICloudBanner && !showsOnboarding
    }

    /// Hides the iCloud banner until iCloud has worked again and fails once more.
    public func dismissICloudBanner() {
        hasDismissedICloudBanner = true
        progress.hasDismissedICloudBanner = true
    }

    /// Records whether the athlete was never asked to allow distance (see
    /// ``ActivityRefreshing/hasUnansweredDistanceAccess()``).
    func setHasUnansweredDistanceAccess(_ value: Bool) {
        hasUnansweredDistanceAccess = value
    }

    /// Whether the week view shows the "Allow distance" banner (MVP2-146): Health is connected but
    /// the distance types were never asked about (the install predates reading them), it wasn't
    /// dismissed, and the introduction isn't up. It goes away once the athlete has answered the
    /// request, whichever way: a refusal only leaves steps without distance and pace.
    public var showsDistanceBanner: Bool {
        isHealthConnected && hasUnansweredDistanceAccess && !hasDismissedDistanceBanner && !showsOnboarding
    }

    /// Hides the "Allow distance" banner for good.
    public func dismissDistanceBanner() {
        hasDismissedDistanceBanner = true
        progress.hasDismissedDistanceBanner = true
    }
}
