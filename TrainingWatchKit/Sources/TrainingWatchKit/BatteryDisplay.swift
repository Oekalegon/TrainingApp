import SwiftUI

/// How the watch's battery is shown on the run screen (WATCH-118): a bar along the very top with a
/// small gap every 10%, coloured by how much is left. Pure arithmetic apart from the colours, so it
/// can be tested; the watch app reads the level from `WKInterfaceDevice`, and `BatteryBar` draws it.
public struct BatteryDisplay: Sendable, Hashable {
    /// The colour band of a charge.
    public enum Band: Sendable, Hashable {
        /// Unknown: the watch doesn't say (the simulator reports -1).
        case unknown
        /// More than 20%.
        case good
        /// More than 10%, up to 20%.
        case low
        /// 5% up to 10%.
        case veryLow
        /// Under 5%.
        case critical
    }

    /// The charge, 0 to 1, or `nil` when the watch doesn't say.
    public let level: Double?
    /// Whether the watch is charging, or full on a charger.
    public let isCharging: Bool

    /// How many parts the bar has: a small gap every 10%.
    public static let segmentCount = 10

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

    /// The colour band: green above 20%, yellow above 10%, orange from 5%, red under 5%. Judged on the
    /// whole percentage that is shown, so 20% is yellow whatever the float's rounding.
    public var band: Band {
        guard let level else { return .unknown }
        let percent = (level * 100).rounded()
        if percent > 20 { return .good }
        if percent > 10 { return .low }
        if percent >= 5 { return .veryLow }
        return .critical
    }

    /// How full part `index` (0 to 9, from the left) of the bar is, 0 to 1: whole parts below the
    /// charge, a part of the one it falls in, and empty above.
    public func fill(ofSegment index: Int) -> Double {
        guard let level else { return 0 }
        return min(max(level * Double(Self.segmentCount) - Double(index), 0), 1)
    }

    /// What VoiceOver says: "Battery 87 percent", "Battery 87 percent, charging" or "Battery level unknown".
    public var spokenText: String {
        guard let level else { return "Battery level unknown" }
        return "Battery \(Int((level * 100).rounded())) percent" + (isCharging ? ", charging" : "")
    }
}

extension BatteryDisplay.Band {
    /// The colour of the filled part of the bar: green, yellow, orange or red, and grey when unknown.
    public var color: Color {
        switch self {
        case .unknown: .gray
        case .good: .green
        case .low: .yellow
        case .veryLow: .orange
        case .critical: .red
        }
    }
}

/// The battery bar of the run screen (WATCH-118): ten parts in a row with a small gap between them,
/// each filled in the band's colour up to the charge and in a dim grey beyond it.
public struct BatteryBar: View {
    public let battery: BatteryDisplay
    public var height: Double

    public init(_ battery: BatteryDisplay, height: Double = 5) {
        self.battery = battery
        self.height = height
    }

    public var body: some View {
        Canvas { context, size in
            let count = BatteryDisplay.segmentCount
            let gap = 2.0
            let width = (size.width - gap * Double(count - 1)) / Double(count)
            for index in 0..<count {
                let x = Double(index) * (width + gap)
                let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                let path = Path(roundedRect: rect, cornerRadius: min(2, size.height / 2))
                context.fill(path, with: .color(.gray.opacity(0.3)))
                let fill = battery.fill(ofSegment: index)
                if fill > 0 {
                    let part = CGRect(x: x, y: 0, width: width * fill, height: size.height)
                    context.fill(
                        Path(roundedRect: part, cornerRadius: min(2, size.height / 2)),
                        with: .color(battery.band.color))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(battery.spokenText)
    }
}
