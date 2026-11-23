import Foundation

/// How the watch's battery is shown on the run screen (WATCH-118): a symbol and a percentage.
/// Pure, so it can be tested; the watch app reads the level from `WKInterfaceDevice`.
public struct BatteryDisplay: Sendable, Hashable {
    /// The charge, 0 to 1, or `nil` when the watch doesn't say (the simulator reports -1).
    public let level: Double?
    /// Whether the watch is charging, or full on a charger.
    public let isCharging: Bool

    /// - Parameters:
    ///   - level: `WKInterfaceDevice.batteryLevel`: 0 to 1, or a negative number when unknown.
    ///   - isCharging: Whether the battery state is charging or full.
    public init(level: Float, isCharging: Bool) {
        self.level = level < 0 ? nil : Double(min(level, 1))
        self.isCharging = isCharging
    }

    /// The charge as a percentage, such as "87%", or "--%" when unknown.
    public var percentText: String {
        level.map { "\(Int(($0 * 100).rounded()))%" } ?? "--%"
    }

    /// Whether the charge is low enough to show in red: 20% or less and not charging.
    public var isLow: Bool {
        guard let level else { return false }
        // By the whole percentage that is shown, so 20% reads as low whatever the float's rounding.
        return Int((level * 100).rounded()) <= 20 && !isCharging
    }

    /// The SF Symbol for the charge, in quarters; the charging one has a bolt.
    public var symbolName: String {
        if isCharging { return "battery.100percent.bolt" }
        guard let level else { return "battery.0percent" }
        switch level {
        case ..<0.125: return "battery.0percent"
        case ..<0.375: return "battery.25percent"
        case ..<0.625: return "battery.50percent"
        case ..<0.875: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// What VoiceOver says: "Battery 87 percent", "Battery 87 percent, charging" or "Battery level unknown".
    public var spokenText: String {
        guard let level else { return "Battery level unknown" }
        return "Battery \(Int((level * 100).rounded())) percent" + (isCharging ? ", charging" : "")
    }
}
