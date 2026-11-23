import SwiftUI

/// The battery bar of the run screen (WATCH-118): ten parts in a row with a small gap between them,
/// each filled in the band's colour up to the charge and in a dim grey beyond it.
public struct BatteryBar: View {
    public let battery: BatteryDisplay
    public var height: Double
    /// The colour of the filled part: the forecast's verdict in a planned workout, otherwise (`nil`)
    /// the colour of the charge itself.
    public var tint: Color?

    public init(_ battery: BatteryDisplay, height: Double = 5, tint: Color? = nil) {
        self.battery = battery
        self.height = height
        self.tint = tint
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
                        with: .color(tint ?? battery.band.color))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(battery.spokenText)
    }
}
