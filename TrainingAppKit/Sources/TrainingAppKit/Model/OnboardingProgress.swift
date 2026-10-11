import Foundation

/// What the athlete has already done with the first-run introduction and the permission banners
/// (MVP2-147), so none of them comes back once dealt with.
///
/// A seam rather than `UserDefaults` directly, like ``MaxHeartRatePromptHistory``. The app uses
/// ``UserDefaultsOnboardingProgress``.
@MainActor
public protocol OnboardingProgress: AnyObject {
    /// Whether the first-run introduction has been shown and left, by continuing or skipping.
    var hasCompletedOnboarding: Bool { get set }
    /// Whether the athlete dismissed the week view's "Connect Health Data" banner.
    var hasDismissedHealthBanner: Bool { get set }
    /// Whether the athlete dismissed the "iCloud isn't available" banner.
    var hasDismissedICloudBanner: Bool { get set }
}
