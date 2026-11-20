import Foundation

/// The part of a WatchConnectivity session the zone channel uses, so the channel's logic can be
/// tested with a fake (WatchConnectivity doesn't exist on macOS, where `swift test` runs).
@MainActor
public protocol WatchSessionControlling: AnyObject {
    /// Whether the session is active and can send.
    var isActivated: Bool { get }
    /// Whether a send can reach a watch: on the phone, a watch is paired and has the app installed;
    /// always `false` on the watch.
    var canReceiveContext: Bool { get }
    /// Starts the session.
    func activate()
    /// Replaces the application context sent to the other device.
    func updateContext(_ context: [String: Any]) throws
}

/// Moves the athlete's zones from the iPhone to the watch (WATCH-102), over a
/// ``WatchSessionControlling`` session, which is WatchConnectivity in the apps.
///
/// The phone calls ``send(_:)``; the watch gets each new value through the closure it passed to
/// ``activate(onReceive:)``, and also the latest one that arrived while its app wasn't running.
/// An application context fits because only the newest zones matter and the system delivers the
/// last one when the other app next runs. The channel keeps the latest zones and sends them again
/// whenever the session becomes active or the watch state changes (a watch paired, or the app
/// installed), so a send at launch isn't lost and a watch added later still gets them. A CloudKit
/// fallback for a phone that isn't reachable comes later (WATCH-114).
@MainActor
public final class WatchZoneChannel: WatchZoneSending {
    private let session: any WatchSessionControlling
    private var onReceive: ((WatchZones) -> Void)?
    private var latest: WatchZones?
    /// Whether `latest` still has to go out: set by a new send and by a change in the watch state.
    private var needsSend = false

    /// Why the last attempt to hand the zones to the session failed; `nil` when it worked or none
    /// was made.
    public private(set) var lastSendError: String?

    public init(session: any WatchSessionControlling) {
        self.session = session
    }

    /// A channel on WatchConnectivity, or `nil` where it isn't supported.
    public static func live() -> WatchZoneChannel? {
        #if canImport(WatchConnectivity)
        WCSessionAdapter.makeChannel()
        #else
        nil
        #endif
    }

    /// Starts the session. On the watch, `onReceive` gets the zones already waiting and each new
    /// set that arrives; on the phone it isn't used.
    public func activate(onReceive: ((WatchZones) -> Void)? = nil) {
        self.onReceive = onReceive
        session.activate()
    }

    /// Sends the zones to the watch, replacing any not yet delivered. They are held until the
    /// session is active and a watch with the app installed is paired.
    ///
    /// - Throws: An encoding error.
    public func send(_ zones: WatchZones) throws {
        _ = try zones.applicationContext()
        latest = zones
        needsSend = true
        sendIfNeeded()
    }

    /// The session finished activating; `receivedData` is the zones context it already holds.
    func sessionActivated(receivedData: Data?) {
        sendIfNeeded()
        if let receivedData { received(data: receivedData) }
    }

    /// A watch was paired or the watch app installed or removed: send the zones again.
    func watchStateChanged() {
        needsSend = latest != nil
        sendIfNeeded()
    }

    /// Zones arrived from the other device.
    func received(data: Data) {
        guard let zones = WatchZones(data: data) else { return }
        onReceive?(zones)
    }

    private func sendIfNeeded() {
        guard needsSend, let latest, session.isActivated, session.canReceiveContext else { return }
        do {
            try session.updateContext(try latest.applicationContext())
            needsSend = false
            lastSendError = nil
        } catch {
            lastSendError = error.localizedDescription
        }
    }
}
