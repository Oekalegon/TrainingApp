import GeoCore
import MapUI
import SwiftUI

/// A route drawn over the athlete's selected map (MVP4-101). Where there is no map to show it says why, in words, and not an empty
/// frame: no map yet, the route is outside the map, or the map can't be opened.
public struct RouteMapView: View {
    @State private var viewModel: RouteMapViewModel

    public init(viewModel: RouteMapViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        GeometryReader { geometry in
            content
                .frame(width: geometry.size.width, height: geometry.size.height)
                .task(id: geometry.size) { viewModel.load(viewSize: geometry.size) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            ProgressView()
        case .noMap:
            message("No Map", systemImage: "map", text: "Add a map under Athlete ▸ Maps to see your route on it.")
        case .outsideMap(let name):
            message("Outside the Map", systemImage: "map", text: "This route is not on \(name). Add a map that covers it under Athlete ▸ Maps.")
        case .failed(let text):
            message("Map Not Available", systemImage: "exclamationmark.triangle", text: text)
        case .ready(let ready):
            RouteMapReadyView(ready: ready)
                // A new map (or a new route position) is a new view: the kit reads its source once, when the view is made.
                .id(ready.map.id)
        }
    }

    private func message(_ title: LocalizedStringKey, systemImage: String, text: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(text))
    }
}

/// The map itself, with the centre and zoom the athlete changes by panning and pinching, starting where the route fits.
private struct RouteMapReadyView: View {
    let ready: RouteMapViewModel.Ready
    @State private var center: Coordinate
    @State private var zoom: Double

    init(ready: RouteMapViewModel.Ready) {
        self.ready = ready
        _center = State(initialValue: ready.center)
        _zoom = State(initialValue: ready.zoom)
    }

    var body: some View {
        MapView(source: ready.map.source, center: $center, zoom: $zoom, bearing: .constant(0), overlays: [ready.overlay])
            .accessibilityLabel("Map of the route")
    }
}
