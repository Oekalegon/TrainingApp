import SwiftUI
import UniformTypeIdentifiers

/// Athlete ▸ Maps (MVP4-101): the maps on the phone, one of which is shown. A map is a `.gmk` file or a folder of blocks made with
/// GeoMapKit (the kit's demo app builds them on the Mac); add one from Files. The map with the check mark is the one routes are drawn on.
struct MapsView: View {
    let library: MapLibrary
    @State private var isAdding = false
    @State private var errors: [MapLibraryError] = []
    @State private var pendingDelete: MapItem?

    private static let mapType = UTType(filenameExtension: "gmk") ?? .data

    var body: some View {
        List {
            Section {
                ForEach(library.maps) { map in
                    Button { library.selectedMapID = map.id } label: { row(map) }
                        .foregroundStyle(.primary)
                        .swipeActions { Button("Delete", role: .destructive) { pendingDelete = map } }
                }
                Button("Add Map", systemImage: "plus") { isAdding = true }
            } header: {
                Text("Maps")
            } footer: {
                Text((library.maps.isEmpty
                    ? "Add a .gmk map file, or a folder of map blocks, from Files. Maps are made with GeoMapKit."
                    : "Routes are drawn on the map with the check mark. A big map or a folder stays where it is: deleting it here doesn't delete the original.")
                    + " Map data © OpenStreetMap contributors, available under the Open Database Licence.")
            }
            if library.selectedMap != nil {
                Section {
                    NavigationLink("Show Map") { MapPreviewView(library: library) }
                    NavigationLink("Show a GPX Route") { GPXRouteMapScreen(library: library) }
                }
            }
            if !errors.isEmpty {
                Section {
                    ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                        Text(error.localizedDescription).foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle(AthleteRoute.maps.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .fileImporter(isPresented: $isAdding, allowedContentTypes: [Self.mapType, .folder], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): errors = library.add(urls).errors
            case .failure(let error): errors = [.unreadable("The file", error.localizedDescription)]
            }
        }
        .confirmationDialog(
            "Delete this map?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible, presenting: pendingDelete
        ) { map in
            Button("Delete \(map.name)", role: .destructive) {
                do { try library.delete(map) } catch { errors = [.unreadable(map.name, error.localizedDescription)] }
            }
        } message: { map in
            Text(map.kind == .file ? "The copy in the app is deleted." : "The link is removed. The original stays where it is.")
        }
        .onAppear { library.reload() }
    }

    private func row(_ map: MapItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(map.name)
                Text(Self.detail(map)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if map.id == library.selectedMapID {
                Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityLabel("Selected")
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "42 MB", "Folder of blocks" or "Linked file".
    static func detail(_ map: MapItem) -> String {
        switch map.kind {
        case .file: map.bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Map file"
        case .blocks: "Folder of blocks"
        case .linkedFile: "Linked file"
        }
    }
}
