import Foundation

/// ``OnboardingProgress`` stored in `UserDefaults`.
///
/// Local to this device, not synced: a new device explains Health and iCloud again, which is right,
/// since permissions are per device.
@MainActor
public final class UserDefaultsOnboardingProgress: OnboardingProgress {
    private static let completedKey = "onboarding.hasCompleted"
    private static let healthBannerKey = "onboarding.hasDismissedHealthBanner"
    private static let iCloudBannerKey = "onboarding.hasDismissedICloudBanner"
    private static let distanceBannerKey = "onboarding.hasDismissedDistanceBanner"
    private let defaults: UserDefaults

    /// - Parameter defaults: Where to store the progress; defaults to `.standard`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Self.completedKey) }
        set { defaults.set(newValue, forKey: Self.completedKey) }
    }

    public var hasDismissedHealthBanner: Bool {
        get { defaults.bool(forKey: Self.healthBannerKey) }
        set { defaults.set(newValue, forKey: Self.healthBannerKey) }
    }

    public var hasDismissedICloudBanner: Bool {
        get { defaults.bool(forKey: Self.iCloudBannerKey) }
        set { defaults.set(newValue, forKey: Self.iCloudBannerKey) }
    }

    public var hasDismissedDistanceBanner: Bool {
        get { defaults.bool(forKey: Self.distanceBannerKey) }
        set { defaults.set(newValue, forKey: Self.distanceBannerKey) }
    }
}
