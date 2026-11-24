import Foundation

/// The part of a WatchConnectivity session the channel uses, so the channel's logic can be tested
/// with a fake (WatchConnectivity doesn't exist on macOS, where `swift test` runs).
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

/// Something that puts the athlete's zones and plan on the watch: ``WatchSyncChannel`` on the
/// phone, a fake in tests.
@MainActor
public protocol WatchSyncSending: AnyObject {
    /// Sends the zones, replacing any that haven't been delivered yet. The plan sent before stays.
    func send(zones: WatchZones) throws

    /// Sends the plan, replacing any that hasn't been delivered yet. The zones sent before stay.
    func send(plan: WatchPlan) throws

    /// Sends the sound and haptic settings (WATCH-107), replacing any that haven't been delivered.
    func send(cues: CueSettings) throws

    /// Why the last attempt to hand the context to the transport failed, or `nil` when it worked.
    var lastSendError: String? { get }
}

/// Moves what the iPhone knows to the watch (WATCH-102 zones, WATCH-103 plan), over a
/// ``WatchSessionControlling`` session, which is WatchConnectivity in the apps.
///
/// The phone calls ``send(zones:)`` and ``send(plan:)``; the watch gets each new context through
/// the closure it passed to ``activate(onReceive:)``, and also the latest one that arrived while
/// its app wasn't running. An application context fits because only the newest values matter and
/// the system delivers the last one when the other app next runs. The two kinds of value are one
/// context, since each context replaces the one before it as a whole. The channel keeps what it was
/// given and sends it again whenever the session becomes active or the watch state changes (a watch
/// paired, or the app installed), so a send at launch isn't lost and a watch added later still
/// gets everything. A CloudKit fallback for a phone that isn't reachable comes later (WATCH-114).
@MainActor
public final class WatchSyncChannel: WatchSyncSending {
    private let session: any WatchSessionControlling
    private var onReceive: ((WatchContext) -> Void)?
    private var latest = WatchContext()
    /// Whether `latest` still has to go out: set by a new send and by a change in the watch state.
    private var needsSend = false

    /// Why the last attempt to hand the context to the session failed; `nil` when it worked or
    /// none was made.
    public private(set) var lastSendError: String?

    public init(session: any WatchSessionControlling) {
        self.session = session
    }

    /// A channel on WatchConnectivity, or `nil` where it isn't supported.
    public static func live() -> WatchSyncChannel? {
        #if canImport(WatchConnectivity)
        WCSessionAdapter.makeChannel()
        #else
        nil
        #endif
    }

    /// Starts the session. On the watch, `onReceive` gets the context already waiting and each new
    /// one that arrives; on the phone it isn't used.
    public func activate(onReceive: ((WatchContext) -> Void)? = nil) {
        self.onReceive = onReceive
        session.activate()
    }

    /// - Throws: An encoding error.
    public func send(zones: WatchZones) throws {
        var context = latest
        context.zones = zones
        try hold(context)
    }

    /// - Throws: An encoding error.
    public func send(plan: WatchPlan) throws {
        var context = latest
        context.plan = plan
        try hold(context)
    }

    /// - Throws: An encoding error.
    public func send(cues: CueSettings) throws {
        var context = latest
        context.cues = cues
        try hold(context)
    }

    private func hold(_ context: WatchContext) throws {
        _ = try context.applicationContext()
        latest = context
        needsSend = true
        sendIfNeeded()
    }

    /// The session finished activating; `receivedData` is the context it already holds.
    func sessionActivated(receivedData: Data?) {
        sendIfNeeded()
        if let receivedData { received(data: receivedData) }
    }

    /// A watch was paired or the watch app installed or removed: send the context again.
    func watchStateChanged() {
        needsSend = latest != WatchContext()
        sendIfNeeded()
    }

    /// A context arrived from the other device.
    func received(data: Data) {
        guard let context = WatchContext(data: data) else { return }
        onReceive?(context)
    }

    private func sendIfNeeded() {
        guard needsSend, session.isActivated, session.canReceiveContext else { return }
        do {
            try session.updateContext(try latest.applicationContext())
            needsSend = false
            lastSendError = nil
        } catch {
            lastSendError = error.localizedDescription
        }
    }
}
