import Foundation

extension WatchZones {
    /// The key the zones travel under in a WatchConnectivity application context.
    static let contextKey = "heartRateZones"

    /// The application context that carries these zones to the other device. The latest context
    /// replaces the one before it, which is what a "current zones" value wants: the watch needs
    /// the newest settings, not a history.
    public func applicationContext() throws -> [String: Any] {
        [Self.contextKey: try JSONEncoder().encode(self)]
    }

    /// The zones in an application context, or `nil` when it holds none or they can't be decoded.
    public init?(applicationContext: [String: Any]) {
        guard let data = applicationContext[Self.contextKey] as? Data else { return nil }
        self.init(data: data)
    }

    /// The zones in encoded form, or `nil` when they can't be decoded.
    public init?(data: Data) {
        guard let zones = try? JSONDecoder().decode(WatchZones.self, from: data) else { return nil }
        self = zones
    }
}

/// Something that puts the athlete's zones on the watch: ``WatchZoneChannel`` on the phone, a fake
/// in tests.
@MainActor
public protocol WatchZoneSending {
    /// Sends the zones, replacing any that have not been delivered yet.
    func send(_ zones: WatchZones) throws
}
