import Foundation

/// A download of a map that a sheet shows (MVP4-102): the area and the model that gets it. They travel together, so the sheet that
/// is shown for the item always has its model.
struct MapDownloadRequest: Identifiable {
    let area: MapArea
    let model: MapDownloadModel
    var id: String { area.id }
}
