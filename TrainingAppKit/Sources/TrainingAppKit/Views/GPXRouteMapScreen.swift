import SwiftUI
import Tracks
import UniformTypeIdentifiers
import MapLibrary

/// Picks a GPX file and shows its route on the selected map (MVP4-101), opened from Athlete ▸ Maps: a way to see a course on the map
/// before planned workouts and Health routes feed `RouteMapView`.
struct GPXRouteMapScreen: View {
    let library: MapLibrary
    @State private var viewModel: RouteMapViewModel?
    @State private var routeName: String?
    @State private var isPicking = false
    @State private var errorText: String?

    private static let gpxType = UTType(filenameExtension: "gpx") ?? .xml

    var body: some View {
        Group {
            if let viewModel {
                RouteMapView(viewModel: viewModel)
            } else {
                ContentUnavailableView {
                    Label("No Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                } description: {
                    Text(errorText ?? "Choose a GPX file to see its route on your map.")
                } actions: {
                    Button("Choose GPX File") { isPicking = true }
                }
            }
        }
        .navigationTitle(routeName ?? "GPX Route")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if viewModel != nil {
                ToolbarItem(placement: .primaryAction) { Button("Choose", systemImage: "folder") { isPicking = true } }
            }
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [Self.gpxType, .xml]) { result in
            switch result {
            case .success(let url):
                do {
                    let route = try GPXRouteLoader.route(contentsOf: url)
                    routeName = route.name ?? url.deletingPathExtension().lastPathComponent
                    errorText = nil
                    viewModel = RouteMapViewModel(route: route, library: library)
                } catch {
                    errorText = error.localizedDescription
                }
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
    }
}
