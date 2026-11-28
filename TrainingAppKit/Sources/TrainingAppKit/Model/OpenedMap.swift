import Foundation
import FeatureStore
import GeoCore

/// A map that is open (MVP4-101): where its cells come from, the area it covers and the credit it needs. A linked folder or
/// file is held open (security-scoped access) until this is released.
public final class OpenedMap: @unchecked Sendable {
    /// The id of the map's ``MapItem``.
    public let id: String
    public let source: any CellSource
    /// The area the map covers, or `nil` when the source doesn't say.
    public let bounds: BoundingBox?
    /// The data credit that goes with the map (the OpenStreetMap licence asks for it to be shown).
    public let attribution: String
    private let accessed: [URL]

    init(id: String, source: any CellSource, bounds: BoundingBox?, accessed: [URL] = []) {
        self.id = id
        self.source = source
        self.bounds = bounds
        self.attribution = source.attribution
        self.accessed = accessed
    }

    deinit {
        for url in accessed { url.stopAccessingSecurityScopedResource() }
    }
}
