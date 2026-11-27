import SwiftUI

/// The outline of a watch case: a rounded rectangle, with, for the Ultra, a guard that bulges out of its right side
/// in one curve (WATCH-142). The guard is part of the case, not a part stuck on it: the edge leaves the case in a
/// smooth S-curve, runs down the guard, and returns the same way.
struct WatchCaseShape: Shape {
    /// The corner radius of the case.
    let cornerRadius: Double
    /// How far the guard stands out of the case's right edge; 0 draws a plain rounded rectangle.
    let guardWidth: Double
    /// The guard's top and bottom, where its outer edge starts and ends, measured from the top of the case.
    let guardTop: Double
    let guardBottom: Double
    /// How far above and below those the case's edge starts to leave its straight line.
    let shoulder: Double

    /// The rectangle passed holds the case and, on its right, the guard.
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = cornerRadius
        let height = rect.height
        guard guardWidth > 0 else {
            return Path(roundedRect: rect, cornerRadius: r, style: .continuous)
        }
        let right = rect.maxX - guardWidth
        let outer = rect.maxX
        let top = rect.minY + guardTop - shoulder
        let topEnd = rect.minY + guardTop + shoulder * 0.6
        let bottomStart = rect.minY + guardBottom - shoulder * 0.6
        let bottom = rect.minY + guardBottom + shoulder
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: right - r, y: rect.minY))
        path.addArc(
            center: CGPoint(x: right - r, y: rect.minY + r), radius: r,
            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: right, y: top))
        // Out onto the guard.
        let mid1 = (top + topEnd) / 2
        path.addCurve(
            to: CGPoint(x: outer, y: topEnd),
            control1: CGPoint(x: right, y: mid1), control2: CGPoint(x: outer, y: mid1))
        path.addLine(to: CGPoint(x: outer, y: bottomStart))
        // And back.
        let mid2 = (bottomStart + bottom) / 2
        path.addCurve(
            to: CGPoint(x: right, y: bottom),
            control1: CGPoint(x: outer, y: mid2), control2: CGPoint(x: right, y: mid2))
        path.addLine(to: CGPoint(x: right, y: rect.minY + height - r))
        path.addArc(
            center: CGPoint(x: right - r, y: rect.minY + height - r), radius: r,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY + height))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + height - r), radius: r,
            startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
            startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}
