#if canImport(WatchConnectivity)
import Foundation
import OSLog
import WatchConnectivity

/// Moves the athlete's zones from the iPhone to the watch with WatchConnectivity (WATCH-102).
///
/// The phone calls ``send(_:)``; the watch gets each new value through the closure it passed to
/// ``activate(onReceive:)``, and also the latest one that arrived while its app wasn't running.
/// An application context fits because only the newest zones matter and the system delivers the
/// last one when the other app next runs. A CloudKit fallback for a phone that isn't reachable
/// comes later (WATCH-114).
@MainActor
public final class WatchZoneChannel: NSObject {
    private var onReceive: ((WatchZones) -> Void)?

    public override init() {
        super.init()
    }

    /// Whether WatchConnectivity works here (not on every device).
    public static var isSupported: Bool { WCSession.isSupported() }

    /// Starts the session. On the watch, `onReceive` gets the zones already waiting and each new
    /// set that arrives; on the phone it isn't used.
    public func activate(onReceive: ((WatchZones) -> Void)? = nil) {
        guard Self.isSupported else { return }
        self.onReceive = onReceive
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    #if os(iOS)
    /// The zones waiting for a session that can take them.
    private var pending: WatchZones?
    private let log = Logger(subsystem: "org.oekalegon.trainingapp", category: "WatchZoneChannel")

    /// Sends the zones to the paired watch, replacing any not yet delivered. They are held until
    /// the session is active and a watch with the app installed is paired, so sending at launch,
    /// before either is true, isn't lost.
    ///
    /// - Throws: An encoding error.
    public func send(_ zones: WatchZones) throws {
        _ = try zones.applicationContext()
        pending = zones
        sendPending()
    }

    fileprivate func sendPending() {
        guard let zones = pending, Self.isSupported else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext(try zones.applicationContext())
            pending = nil
        } catch {
            log.error("zones not sent: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif
}

#if os(iOS)
extension WatchZoneChannel: WatchZoneSending {}
#endif

extension WatchZoneChannel: WCSessionDelegate {
    nonisolated public func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?
    ) {
        guard activationState == .activated else { return }
        #if os(iOS)
        Task { @MainActor in self.sendPending() }
        #endif
        // The latest context may have arrived while the app wasn't running.
        guard let data = session.receivedApplicationContext[WatchZones.contextKey] as? Data else { return }
        deliver(data)
    }

    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchZones.contextKey] as? Data else { return }
        deliver(data)
    }

    nonisolated private func deliver(_ data: Data) {
        guard let zones = WatchZones(data: data) else { return }
        Task { @MainActor in self.onReceive?(zones) }
    }

    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
        // The watch app was installed or a watch paired: send what was waiting.
        Task { @MainActor in self.sendPending() }
    }

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        // A new watch was paired: start again so the session stays usable.
        session.activate()
    }
    #endif
}
#endif
