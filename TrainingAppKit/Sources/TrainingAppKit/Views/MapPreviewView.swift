import GeoCore
import MapUI
import SwiftUI
import MapLibrary

/// The selected map on its own, to look at what has been added (MVP4-101), opened from Athlete ▸ Maps.
struct MapPreviewView: View {
    let library: MapLibrary
    @State private var opened: OpenedMap?
    @State private var errorText: String?
    @State private var center = Coordinate(latitude: 0, longitude: 0)
    @State private var zoom = 3.0

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let opened {
                    MapView(source: opened.source, center: $center, zoom: $zoom, bearing: .constant(0))
                } else if let errorText {
                    ContentUnavailableView("Map Not Available", systemImage: "exclamationmark.triangle", description: Text(errorText))
                } else {
                    ProgressView()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .task(id: library.selectedMapID) { open(viewSize: geometry.size) }
        }
        .navigationTitle(library.selectedMap?.name ?? "Map")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func open(viewSize: CGSize) {
        guard let item = library.selectedMap else {
            errorText = MapLibraryError.noMap.localizedDescription
            return
        }
        do {
            let map = try library.open(item)
            errorText = nil
            if let bounds = map.bounds {
                center = WebMercator.center(of: bounds)
                zoom = WebMercator.zoom(fitting: bounds, width: viewSize.width, height: viewSize.height)
            }
            opened = map
        } catch {
            errorText = error.localizedDescription
        }
    }
}
