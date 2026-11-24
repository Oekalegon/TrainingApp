import Foundation
import Observation
import TrainingWatchKit

/// The athlete's choice of how the watch tells them things (WATCH-107): sound through earbuds, the
/// watch's speaker or not at all, haptics, and for each kind of signal a tone, speech or both. Set on the Apple Watch ▸
/// Synchronisation screen, kept here in `UserDefaults` and sent to the watch with the zones and
/// the plan, which keeps the last ones it got.
///
/// `AppTabView` calls ``sync()`` when the app becomes active; a change is sent at once. The
/// transport holds the latest settings until a watch can take them, and sends them again when a watch
/// is paired or the app installed later (see ``WatchSyncChannel``), so one send per launch is enough.
@MainActor
@Observable
public final class WatchCueSync {
    /// The current settings; change them with ``update(_:)``.
    public private(set) var settings: CueSettings
    /// Why the settings couldn't be handed to the watch, or `nil`.
    public var lastError: String? { rejectedError ?? sender.lastSendError }

    @ObservationIgnored private let sender: any WatchSyncSending
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var lastSent: CueSettings?
    private var rejectedError: String?

    public init(sender: any WatchSyncSending, defaults: UserDefaults = .standard) {
        self.sender = sender
        self.defaults = defaults
        settings = CueSettings.stored(in: defaults)
    }

    /// Keeps and sends new settings.
    public func update(_ settings: CueSettings) {
        self.settings = settings
        settings.save(in: defaults)
        sync()
    }

    /// Makes the watch tap `pattern` now (WATCH-117). `false` when the watch app isn't open and
    /// reachable, so the view can say to open it.
    public func preview(haptic pattern: HapticPattern) -> Bool {
        sender.preview(haptic: HapticPlan(pattern))
    }

    /// Sends the settings if they weren't sent yet in this run of the app, or changed since.
    public func sync() {
        guard settings != lastSent else { return }
        do {
            try sender.send(cues: settings)
            lastSent = settings
            rejectedError = nil
        } catch {
            rejectedError = error.localizedDescription
        }
    }
}
