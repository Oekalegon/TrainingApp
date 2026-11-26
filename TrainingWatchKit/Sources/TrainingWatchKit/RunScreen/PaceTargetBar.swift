import SwiftUI

/// The pace bar of a run screen (WATCH-135): a line with the target's stretch bright, slow at the left and fast at
/// the right, and a triangle above and one under it at the current pace. Fractions are 0 (slow end) to 1 (fast end).
public struct PaceTargetBar: View {
    /// The target's stretch of the bar.
    let target: ClosedRange<Double>
    /// Where the pace is, or `nil` before there is one.
    let position: Double?
    /// The colour of the triangles, against the target.
    let tint: Color

    private static let barHeight = 14.0
    private static let markerHeight = 7.0, markerHalfWidth = 4.5, markerGap = 2.0
    private static var room: Double { markerHeight + markerGap }

    public var body: some View {
        Canvas { context, size in
            context.translateBy(x: 0, y: Self.room)
            let bar = CGRect(x: 0, y: 0.15 * Self.barHeight, width: size.width, height: 0.7 * Self.barHeight)
            context.fill(Path(roundedRect: bar, cornerRadius: 3), with: .color(.gray.opacity(0.4)))
            let bright = CGRect(
                x: size.width * target.lowerBound, y: 0, width: size.width * (target.upperBound - target.lowerBound), height: Self.barHeight)
            context.fill(Path(roundedRect: bright, cornerRadius: 3), with: .color(.green))
            guard let position else { return }
            let half = Self.markerHalfWidth
            let x = min(max(size.width * position, half), size.width - half)
            let below = Self.barHeight + Self.markerGap
            var lower = Path()
            lower.move(to: CGPoint(x: x, y: below))
            lower.addLine(to: CGPoint(x: x - half, y: below + Self.markerHeight))
            lower.addLine(to: CGPoint(x: x + half, y: below + Self.markerHeight))
            lower.closeSubpath()
            var upper = Path()
            upper.move(to: CGPoint(x: x, y: -Self.markerGap))
            upper.addLine(to: CGPoint(x: x - half, y: -Self.markerGap - Self.markerHeight))
            upper.addLine(to: CGPoint(x: x + half, y: -Self.markerGap - Self.markerHeight))
            upper.closeSubpath()
            context.fill(lower, with: .color(tint))
            context.fill(upper, with: .color(tint))
        }
        .frame(height: Self.barHeight + 2 * Self.room)
        .accessibilityHidden(true)
    }
}
