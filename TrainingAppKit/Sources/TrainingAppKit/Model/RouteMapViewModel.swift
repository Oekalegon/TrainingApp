import Foundation
import GeoCore
import Observation
import TrackOverlays
import Tracks

/// What a map of one route shows (MVP4-101): the athlete's selected map with the route drawn over it, or the reason there is no
/// map to show. The route comes from outside (the workout's route from Health, a planned workout's course, later); this only
/// decides what to show.
@MainActor
@Observable
public final class RouteMapViewModel {
    /// Everything a map view needs to draw.
    public struct Ready {
        public let map: OpenedMap
        public let center: Coordinate
        public let zoom: Double
        /// One overlay for the model's life, so the map keeps its drawn image when the view is built again.
        public let overlay: RouteOverlay
    }

    public enum State {
        case idle
        /// The library has no map: say how to add one.
        case noMap
        /// The route is outside the selected map.
        case outsideMap(mapName: String)
        case ready(Ready)
        /// The selected map could not be opened.
        case failed(String)
    }

    public private(set) var state: State = .idle
    public let route: Route
    let library: MapLibrary

    public init(route: Route, library: MapLibrary) {
        self.route = route
        self.library = library
    }

    /// The area to download a map for: the route with a margin, named after the route.
    public var downloadArea: MapArea { MapArea.covering(route.boundingBox, name: route.name ?? "Route") }

    /// Opens the selected map and works out what to show; call again when the view's size or the selected map changes.
    ///
    /// - Parameter viewSize: The map view's size in points, so the route fits it.
    public func load(viewSize: CGSize) {
        guard let item = library.selectedMap else {
            state = .noMap
            return
        }
        do {
            // A map that is already open for this item is kept: opening it again would drop the drawn image.
            let map: OpenedMap
            if case .ready(let ready) = state, ready.map.id == item.id { map = ready.map } else { map = try library.open(item) }
            switch RouteMapPlan.make(routeBounds: route.boundingBox, mapBounds: map.bounds, viewSize: viewSize) {
            case .outsideMap:
                state = .outsideMap(mapName: item.name)
            case .show(let center, let zoom):
                if case .ready(let ready) = state, ready.map.id == map.id {
                    state = .ready(Ready(map: map, center: center, zoom: zoom, overlay: ready.overlay))
                } else {
                    state = .ready(Ready(map: map, center: center, zoom: zoom, overlay: RouteOverlay(route: route)))
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
