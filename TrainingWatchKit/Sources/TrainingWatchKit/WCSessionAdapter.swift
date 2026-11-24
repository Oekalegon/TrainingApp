#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

/// `WCSession` behind ``WatchSessionControlling``: starts the session and passes its callbacks on
/// to the ``WatchSyncChannel``.
@MainActor
final class WCSessionAdapter: NSObject {
    weak var channel: WatchSyncChannel?

    /// A channel on the default session, or `nil` where WatchConnectivity isn't supported.
    static func makeChannel() -> WatchSyncChannel? {
        guard WCSession.isSupported() else { return nil }
        let adapter = WCSessionAdapter()
        let channel = WatchSyncChannel(session: adapter)
        adapter.channel = channel
        return channel
    }
}

extension WCSessionAdapter: WatchSessionControlling {
    var isActivated: Bool { WCSession.default.activationState == .activated }

    var canReceiveContext: Bool {
        #if os(iOS)
        WCSession.default.isPaired && WCSession.default.isWatchAppInstalled
        #else
        false
        #endif
    }

    func activate() {
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func updateContext(_ context: [String: Any]) throws {
        try WCSession.default.updateApplicationContext(context)
    }

    func sendPreview(_ message: [String: Any]) -> Bool {
        #if os(iOS)
        guard WCSession.default.isReachable else { return false }
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
        return true
        #else
        false
        #endif
    }
}

extension WCSessionAdapter: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        nonisolated(unsafe) let message = message
        Task { @MainActor in self.channel?.receivedPreview(message) }
    }

    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?
    ) {
        guard activationState == .activated else { return }
        // The latest context may have arrived while the app wasn't running.
        let data = session.receivedApplicationContext[WatchContext.contextKey] as? Data
        Task { @MainActor in self.channel?.sessionActivated(receivedData: data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchContext.contextKey] as? Data else { return }
        Task { @MainActor in self.channel?.received(data: data) }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // A new watch was paired: start again so the session stays usable.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.channel?.watchStateChanged() }
    }
    #endif
}
#endif
