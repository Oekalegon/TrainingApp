import CoreGraphics
import Foundation

/// The geometry of the zone dial (WATCH-118): a ring round the edge of the screen made of six
/// sectors, zone 0 (below zone 1) and zones 1 to 5, each 60 degrees as seen from the middle of the
/// screen. The sector of the step's target zone is centred on the top and the others follow it
/// clockwise, so a change of target turns the whole ring. Angles are in degrees, 0 at the top and
/// growing clockwise.
///
/// Pure arithmetic, so it can be tested without a screen; `ZoneDialRing` draws it.
public enum ZoneDial {
    /// The angle of a sector's middle: the target's is 0, the next zone's 60 degrees on. Not
    /// normalised, so a target that is moving from one zone to the next turns smoothly through the
    /// wrap-around.
    ///
    /// - Parameters:
    ///   - zone: The sector's zone, 0 to 5.
    ///   - target: The target zone, 1 to 5, or between two while the ring turns.
    public static func sectorCenter(zone: Int, target: Double) -> Double {
        (Double(zone) - target) * 60
    }

    /// The angle of a position along the zones (see ``ZoneBands/position(forHeartRate:)``): the
    /// middle of a zone's sector for `n + 0.5`, and its edges for `n.0` and `n + 1.0`.
    ///
    /// - Parameters:
    ///   - position: Where the heart rate is along the zones, 0 to 6.
    ///   - target: The target zone.
    public static func angle(forPosition position: Double, target: Double) -> Double {
        (position - target - 0.5) * 60
    }

    /// The point where a ray from the middle of a rounded rectangle, at `angle`, meets its edge,
    /// and which way the edge faces there.
    ///
    /// - Parameters:
    ///   - angle: Degrees clockwise from the top.
    ///   - size: The rectangle's size.
    ///   - cornerRadius: The radius of its corners, at most half its shorter side.
    /// - Returns: The point, with the origin at the top left of the rectangle, and the angle the
    ///   edge's outward normal points at, in the same degrees.
    public static func edgePoint(
        atAngle angle: Double, size: CGSize, cornerRadius: Double
    ) -> (point: CGPoint, outward: Double) {
        let halfWidth = Double(size.width) / 2
        let halfHeight = Double(size.height) / 2
        let radius = min(max(cornerRadius, 0), halfWidth, halfHeight)
        let radians = angle * .pi / 180
        let dx = sin(radians)
        let dy = -cos(radians)
        // The straight edges first: where the ray meets the plain rectangle.
        let tx = abs(dx) > 1e-12 ? halfWidth / abs(dx) : .infinity
        let ty = abs(dy) > 1e-12 ? halfHeight / abs(dy) : .infinity
        var t = min(tx, ty)
        var normal = tx < ty ? (dx.sign == .minus ? (-1.0, 0.0) : (1.0, 0.0)) : (0.0, dy.sign == .minus ? -1.0 : 1.0)
        var x = dx * t
        var y = dy * t
        // In a corner the edge is the corner's circle instead, whose middle is `radius` in from both sides.
        if abs(x) > halfWidth - radius, abs(y) > halfHeight - radius, radius > 0 {
            let cx = (x < 0 ? -1.0 : 1.0) * (halfWidth - radius)
            let cy = (y < 0 ? -1.0 : 1.0) * (halfHeight - radius)
            let along = dx * cx + dy * cy
            let discriminant = along * along - (cx * cx + cy * cy - radius * radius)
            t = along + max(discriminant, 0).squareRoot()
            x = dx * t
            y = dy * t
            normal = ((x - cx) / radius, (y - cy) / radius)
        }
        let outward = atan2(normal.0, -normal.1) * 180 / .pi
        return (CGPoint(x: halfWidth + x, y: halfHeight + y), outward)
    }
}
