import GeoCore
import MapUI
import SwiftUI

/// The Map tab (MVP4-101): the athlete's selected map across the whole screen, under the status bar and the tab bar, with the athlete's
/// position highlighted and a button that centres on it. Without a map it says so and offers to add one.
struct MapTabView: View {
    let library: MapLibrary
    @State private var location = LocationModel()
    @State private var opened: OpenedMap?
    @State private var errorText: String?
    @State private var center = Coordinate(latitude: 20, longitude: 0)
    @State private var zoom = 2.0
    @State private var bearing = 0.0
    /// The first position found moves the map to it, once; after that the athlete moves it.
    @State private var centresOnFirstFix = true
    /// The size of the map, for fitting a whole map into it (it spans the screen, so it is known once the view is on screen).
    @State private var viewSize = CGSize(width: 400, height: 800)
    @State private var isShowingMaps = false
    @State private var isShowingLocationOff = false
    @Environment(\.scenePhase) private var scenePhase

    /// How far to zoom in on the athlete's position: a neighbourhood.
    private static let positionZoom = 14.0

    var body: some View {
        ZStack {
            mapLayer.ignoresSafeArea()
            controls
        }
        .sheet(isPresented: $isShowingMaps) {
            NavigationStack {
                MapsView(library: library)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isShowingMaps = false } } }
            }
        }
        .alert("Location Is Off", isPresented: $isShowingLocationOff) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Allow TrainingApp to use your location in Settings to see where you are on the map.")
        }
        .task(id: library.selectedMapID) { open() }
        .onAppear { location.start() }
        .onDisappear { location.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { location.start() } else { location.stop() }
        }
        .onChange(of: location.coordinate) { _, found in
            guard centresOnFirstFix, let found, covers(found) else { return }
            centresOnFirstFix = false
            center = found
            zoom = max(zoom, Self.positionZoom)
        }
    }

    @ViewBuilder
    private var mapLayer: some View {
        GeometryReader { proxy in
            Color.clear.onChange(of: proxy.size, initial: true) { _, size in viewSize = size }
            if let opened {
                ZStack {
                    MapView(source: opened.source, center: $center, zoom: $zoom, bearing: $bearing)
                        .id(opened.id)
                    if let coordinate = location.coordinate {
                        UserLocationDotView(
                            coordinate: coordinate, accuracy: location.accuracy, center: center, zoom: zoom, bearing: bearing,
                            size: proxy.size)
                    }
                }
            } else if let errorText {
                ContentUnavailableView {
                    Label("Map Not Available", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("Maps") { isShowingMaps = true }
                }
            } else {
                ContentUnavailableView {
                    Label("No Map", systemImage: "map")
                } description: {
                    Text("Add a map to see where you are and where your routes go.")
                } actions: {
                    Button("Add a Map") { isShowingMaps = true }
                }
            }
        }
        .background(.background)
    }

    /// The buttons over the map, in the safe area so the status bar and the tab bar don't cover them.
    private var controls: some View {
        VStack(spacing: 12) {
            Button { centreOnMe() } label: {
                Image(systemName: location.denied ? "location.slash" : (location.isFollowing && location.coordinate != nil ? "location.fill" : "location"))
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel("Centre on my location")
            Button { isShowingMaps = true } label: {
                Image(systemName: "map").frame(width: 24, height: 24)
            }
            .accessibilityLabel("Maps")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .opacity(opened == nil && errorText == nil ? 0 : 1)
    }

    /// Whether the selected map covers a position (a map that doesn't say what it covers is tried).
    private func covers(_ coordinate: Coordinate) -> Bool {
        opened?.bounds?.contains(coordinate) ?? true
    }

    private func centreOnMe() {
        location.start()
        if let coordinate = location.coordinate {
            centresOnFirstFix = false
            center = coordinate
            zoom = max(zoom, Self.positionZoom)
        } else if location.denied {
            isShowingLocationOff = true
        } else {
            // The position isn't known yet: the first one found moves the map.
            centresOnFirstFix = true
        }
    }

    /// Opens the selected map and looks at the athlete's position if it is on it, and at the whole map if not.
    private func open() {
        guard let item = library.selectedMap else {
            opened = nil
            errorText = nil
            return
        }
        do {
            let map = try library.open(item)
            opened = map
            errorText = nil
            if let found = location.coordinate, map.bounds?.contains(found) ?? true {
                center = found
                zoom = Self.positionZoom
            } else if let bounds = map.bounds {
                center = MapFit.center(of: bounds)
                zoom = MapFit.zoom(fitting: bounds, in: viewSize)
            }
        } catch {
            opened = nil
            errorText = error.localizedDescription
        }
    }
}
