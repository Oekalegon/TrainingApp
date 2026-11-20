import Foundation
import TrainingCore
import TrainingWatchKit

/// Keeps the Apple Watch app's heart-rate zones in step with the athlete's (WATCH-102).
///
/// `AppTabView` calls ``sync(settings:)`` when the app becomes active and whenever the athlete's
/// current heart-rate settings change. Zones are sent only when they differ from the last ones
/// sent in this run of the app, so calling it often is cheap; the first call after launch always
/// sends, which also covers a watch app installed since the last launch. The transport holds the
/// latest zones until a watch with the app installed can take them (see ``WatchZoneChannel``).
@MainActor
public final class WatchZoneSync {
    private let sender: any WatchZoneSending
    private var lastSent: WatchZones?

    /// The last zones that couldn't be sent, for the Athlete tab's Watch screen; `nil` when the
    /// last attempt worked or none was made.
    public private(set) var lastError: String?

    /// - Parameter sender: What puts the zones on the watch.
    public init(sender: any WatchZoneSending) {
        self.sender = sender
    }

    #if os(iOS)
    /// A sync on WatchConnectivity, started now; `nil` on a device that doesn't support it.
    public static func live() -> WatchZoneSync? {
        guard WatchZoneChannel.isSupported else { return nil }
        let channel = WatchZoneChannel()
        channel.activate()
        return WatchZoneSync(sender: channel)
    }
    #endif

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
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
