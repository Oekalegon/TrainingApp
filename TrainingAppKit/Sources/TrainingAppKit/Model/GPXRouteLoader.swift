import Foundation
import Tracks

/// Reads a route from a GPX file (MVP4-101), so a course the athlete has as a GPX file can be shown on the map.
enum GPXRouteLoader {
    enum LoadError: Error, Equatable, LocalizedError {
        /// The file has no route and no track with points.
        case noRoute
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .noRoute: "That GPX file has no route or track to show."
            case .unreadable(let reason): "That file can't be read as GPX (\(reason))."
            }
        }
    }

    /// The first route of the file, or its first track when it has no route.
    static func route(from data: Data) throws -> Route {
        let file: GPXFile
        do { file = try GPXFile(data: data) } catch { throw LoadError.unreadable("\(error)") }
        do {
            if let route = file.routes.first(where: { $0.points.count >= 2 }) { return try route.route() }
            if let track = file.tracks.first(where: { $0.points.count >= 2 }) { return try track.route() }
        } catch { throw LoadError.unreadable("\(error)") }
        throw LoadError.noRoute
    }

    static func route(contentsOf url: URL) throws -> Route {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do { return try route(from: Data(contentsOf: url)) } catch let error as LoadError { throw error } catch {
            throw LoadError.unreadable(error.localizedDescription)
        }
    }
}
