import Foundation
import TrainingCore
import TrainingWatchKit

/// Keeps the Apple Watch app's heart-rate zones in step with the athlete's (WATCH-102).
///
/// `AppTabView` calls ``sync(settings:)`` when the app becomes active and whenever the athlete's
/// current heart-rate settings change. Zones are sent only when they differ from the last ones
/// sent in this run of the app, so calling it often is cheap; the first call after launch always
/// sends. The transport holds the latest zones until a watch with the app installed can take them,
/// and sends them again when a watch is paired or the app installed later (see ``WatchZoneChannel``).
@MainActor
public final class WatchZoneSync {
    private let sender: any WatchZoneSending
    private var lastSent: WatchZones?

    private var rejectedError: String?

    /// Why the zones couldn't be handed to the Watch, for a screen to show: the zones couldn't be
    /// encoded, or the transport refused them; `nil` when the last attempt worked or none was
    /// made. A Watch that isn't paired or has no app yet isn't an error: the transport keeps the
    /// zones until one is.
    public var lastError: String? { rejectedError ?? sender.lastSendError }

    /// - Parameter sender: What puts the zones on the watch.
    public init(sender: any WatchZoneSending) {
        self.sender = sender
    }

    /// A sync on WatchConnectivity, started now; `nil` on a device that doesn't support it.
    public static func live() -> WatchZoneSync? {
        guard let channel = WatchZoneChannel.live() else { return nil }
        channel.activate()
        return WatchZoneSync(sender: channel)
    }

    /// Sends the athlete's current zones to the watch if they changed since the last send.
    ///
    /// - Parameter settings: The athlete's current heart-rate settings; `nil` while none are on
    ///   record, in which case nothing is sent (the watch keeps the zones it has).
    public func sync(settings: HeartRateZoneSettings?) {
        guard let settings else { return }
        let zones = WatchZones(settings: settings)
        guard zones != lastSent else { return }
        do {
            try sender.send(zones)
            lastSent = zones
            rejectedError = nil
        } catch {
            rejectedError = error.localizedDescription
        }
    }
}
