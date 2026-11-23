import SwiftUI

/// A battery warning for the run (WATCH-110): what the temporary warning screen says and the colour it
/// is shown in, the same as the battery bar's status.
public struct BatteryWarning: Sendable, Hashable {
    /// How serious the warning is; each level is a step up.
    public enum Level: Int, Sendable, Hashable, Comparable {
        /// Yellow: the battery is getting low, or will end the workout nearly flat.
        case tight = 1
        /// Orange: critical.
        case critical = 2
        /// Red: it will run out before the workout ends, or is nearly empty.
        case runsOut = 3

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let level: Level
    /// The big words, such as "BATTERY LOW".
    public let title: String
    /// The line under them, such as "12%  ·  ~4% AT END".
    public let detail: String
    /// What VoiceOver announces.
    public let spoken: String

    /// The background of the warning screen: yellow, orange or red, as the battery bar.
    public var color: Color {
        switch level {
        case .tight: .yellow
        case .critical: .orange
        case .runsOut: .red
        }
    }

    /// The colour of the text on ``color``: black on yellow and orange, white on red.
    public var textColor: Color { level == .runsOut ? .white : .black }
}

/// Decides when the battery is worth a warning (WATCH-110): the warning goes up a level, and each
/// level is given once. Pure, so it is tested without a run; the recorder feeds it every few seconds.
///
/// The level comes from the forecast when there is one (yellow tight, orange critical, red when it will
/// run out), and from the charge itself otherwise and as a floor (20% or less is tight, 10% or less
/// critical, under 5% runs out), whichever is worse. A charging battery gives none.
///
/// A warning that was given is not repeated when the level wavers: the level has to stay lower for
/// ``recoveryDwell`` before the next rise is a new warning.
public struct BatteryWarningTracker: Sendable {
    /// How long the level has to stay below the one that was warned about before it counts as recovered.
    public static let recoveryDwell: TimeInterval = 120

    private var warned: BatteryWarning.Level?
    private var lowerSince: TimeInterval?

    public init() {}

    /// The level the battery is at now, or `nil` for none.
    ///
    /// - Parameters:
    ///   - battery: The battery now.
    ///   - projection: The forecast for the end of the workout, if there is one.
    public static func level(battery: BatteryDisplay, projection: BatteryProjection?) -> BatteryWarning.Level? {
        guard !battery.isCharging else { return nil }
        let fromCharge: BatteryWarning.Level? = switch battery.band {
        case .unknown, .good: nil
        case .low: .tight
        case .veryLow: .critical
        case .critical: .runsOut
        }
        let fromForecast: BatteryWarning.Level? = switch projection?.verdict {
        case .none, .some(.enough): nil
        case .some(.tight): .tight
        case .some(.critical): .critical
        case .some(.runsOut): .runsOut
        }
        return [fromCharge, fromForecast].compactMap { $0 }.max()
    }

    /// Takes the battery now and says whether to warn.
    ///
    /// - Parameters:
    ///   - battery: The battery now.
    ///   - projection: The forecast for the end of the workout, if there is one.
    ///   - time: The workout time in seconds.
    /// - Returns: A warning when the level went above the highest one given so far, otherwise `nil`.
    public mutating func update(
        battery: BatteryDisplay, projection: BatteryProjection?, at time: TimeInterval
    ) -> BatteryWarning? {
        let level = Self.level(battery: battery, projection: projection)
        // A rise above the highest level warned about (or the first level at all) is a warning.
        if let level, warned.map({ level > $0 }) ?? true {
            warned = level
            lowerSince = nil
            return Self.warning(level: level, battery: battery, projection: projection)
        }
        // Below the level warned about: once it has stayed there for a while, that level is forgotten, so a
        // later rise warns again. At or above it, the wait starts over.
        guard let current = warned, level.map({ $0 < current }) ?? true else {
            lowerSince = nil
            return nil
        }
        if let since = lowerSince {
            if time - since >= Self.recoveryDwell {
                warned = level
                lowerSince = nil
            }
        } else {
            lowerSince = time
        }
        return nil
    }

    private static func warning(
        level: BatteryWarning.Level, battery: BatteryDisplay, projection: BatteryProjection?
    ) -> BatteryWarning {
        let title: String
        switch level {
        case .tight: title = "BATTERY LOW"
        case .critical: title = "BATTERY CRITICAL"
        case .runsOut: title = projection?.verdict == .runsOut ? "BATTERY WON'T LAST" : "BATTERY NEARLY EMPTY"
        }
        let detail = projection.map { "\(battery.percentText)  ·  \($0.text)" } ?? "\(battery.percentText) LEFT"
        let spoken = "\(title.lowercased()), \(battery.percentText.replacingOccurrences(of: "%", with: " percent"))"
            + (projection.map { ", " + $0.spoken } ?? "")
        return BatteryWarning(level: level, title: title, detail: detail, spoken: spoken)
    }
}
