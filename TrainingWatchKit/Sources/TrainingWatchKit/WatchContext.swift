import Foundation

/// Everything the phone sends to the watch in one go. A WatchConnectivity application context
/// replaces the one before it as a whole, so the zones and the plan travel together: sending them
/// separately would let each wipe out the other.
///
/// Each part is read on its own: one the watch can't decode (a phone updated before the watch
/// gained a newer workout format, say) is left out, and the other part still arrives.
public struct WatchContext: Sendable, Codable, Hashable {
    /// The athlete's heart-rate zones; `nil` while the phone has none to send.
    public var zones: WatchZones?
    /// The upcoming planned workouts; `nil` while the phone hasn't sent any yet (an empty
    /// ``WatchPlan`` is "nothing planned", which is different).
    public var plan: WatchPlan?

    /// How the athlete wants to be told by sound and haptics (WATCH-107); `nil` while the phone
    /// hasn't sent them, and the watch keeps the ones it has.
    public var cues: CueSettings?

    /// The run screens the athlete set up (WATCH-109); `nil` while the phone hasn't sent any.
    public var screens: RunScreenConfig?

    public init(zones: WatchZones? = nil, plan: WatchPlan? = nil, cues: CueSettings? = nil, screens: RunScreenConfig? = nil) {
        self.zones = zones
        self.plan = plan
        self.cues = cues
        self.screens = screens
    }

    private enum CodingKeys: String, CodingKey {
        case zones, plan, cues, screens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zones = (try? container.decodeIfPresent(WatchZones.self, forKey: .zones)) ?? nil
        plan = (try? container.decodeIfPresent(WatchPlan.self, forKey: .plan)) ?? nil
        cues = (try? container.decodeIfPresent(CueSettings.self, forKey: .cues)) ?? nil
        screens = (try? container.decodeIfPresent(RunScreenConfig.self, forKey: .screens)) ?? nil
    }
}

extension WatchContext {
    /// The key the context travels under in a WatchConnectivity application context.
    static let contextKey = "watchContext.v1"

    /// The application context that carries this to the other device.
    public func applicationContext() throws -> [String: Any] {
        [Self.contextKey: try JSONEncoder().encode(self)]
    }

    /// The context in encoded form, or `nil` when it can't be decoded.
    public init?(data: Data) {
        guard let context = try? JSONDecoder().decode(WatchContext.self, from: data) else { return nil }
        self = context
    }

    /// The context in an application context, or `nil` when it holds none.
    public init?(applicationContext: [String: Any]) {
        guard let data = applicationContext[Self.contextKey] as? Data else { return nil }
        self.init(data: data)
    }
}
