import GeoCore
import MapRender
import SwiftUI

/// Where the athlete is on the map (MVP4-101): a blue dot with a white ring, a soft circle for how far off the position can be, and a
/// halo that pulses so it stands out on any map. The map's overlays are part of its cached image, so the dot is a view over the map,
/// placed with the same viewport as the map.
struct UserLocationDotView: View {
    let coordinate: Coordinate
    let accuracy: Double?
    let center: Coordinate
    let zoom: Double
    let bearing: Double
    let size: CGSize
    @State private var pulses = false

    var body: some View {
        let point = MapViewport(center: center, zoom: zoom, width: size.width, height: size.height, bearing: bearing).screenPoint(for: coordinate)
        let accuracyRadius = accuracy.map { MapFit.points(forMeters: $0, atLatitude: coordinate.latitude, zoom: zoom) } ?? 0
        ZStack {
            // How far off the position can be, when that is more than the dot.
            if accuracyRadius > 12 {
                Circle().fill(Color.blue.opacity(0.12)).overlay(Circle().stroke(Color.blue.opacity(0.3), lineWidth: 1))
                    .frame(width: accuracyRadius * 2, height: accuracyRadius * 2)
            }
            Circle().fill(Color.blue.opacity(0.25)).frame(width: pulses ? 44 : 22, height: pulses ? 44 : 22).opacity(pulses ? 0 : 1)
            Circle().fill(.blue).frame(width: 16, height: 16)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.3), radius: 2)
        }
        .position(x: point.x, y: point.y)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your location")
        .onAppear { withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulses = true } }
    }
}
