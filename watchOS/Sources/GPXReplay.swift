#if targetEnvironment(simulator)
import CoreLocation

/// Plays a GPX track as GPS fixes in simulator builds, which otherwise get no location.
///
/// The simulator shares the Mac's file system, so the app reads the file directly, with no
/// location permission and no `simctl location`. The file is the `gpxPath` default (launch
/// argument `-gpxPath /path/track.gpx`) or else the first `.gpx` file in
/// `~/Documents/TrainingWatchGPX/`. `gpxSpeed` (default 10) speeds the track up and
/// `gpxStartMinute` (default 0) skips the first part of it. Never commit a GPX file: it holds
/// real locations.
@MainActor
final class GPXReplay {
    private var task: Task<Void, Never>?

    /// The file to play, or `nil` when none is set up and CoreLocation should be used instead.
    static var fileToPlay: String? {
        if let path = UserDefaults.standard.string(forKey: "gpxPath") { return path }
        // The simulator's home directory is its own; the Mac's comes from SIMULATOR_HOST_HOME.
        guard let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else { return nil }
        let folder = home + "/Documents/TrainingWatchGPX"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return files.sorted().first { $0.lowercased().hasSuffix(".gpx") }.map { folder + "/" + $0 }
    }

    /// Starts playing `path`, calling `onFix` for each fix (stamped with the current time, as a
    /// real fix would be) and `onError` when the file has no usable points.
    func start(path: String, onFix: @escaping (CLLocation) -> Void, onError: @escaping (String) -> Void) {
        let defaults = UserDefaults.standard
        let speed = defaults.double(forKey: "gpxSpeed") > 0 ? defaults.double(forKey: "gpxSpeed") : 10
        let startMinute = defaults.double(forKey: "gpxStartMinute")
        task?.cancel()
        task = Task {
            // A track is thousands of points; parse it off the main actor.
            let track = await Task.detached { Self.parse(path: path) }.value
            guard let first = track.first else {
                onError("no GPX points at \(path)")
                return
            }
            let origin = first.time.addingTimeInterval(startMinute * 60)
            let began = Date.now
            var lastEmitted = -1.0
            for point in track where point.time >= origin {
                if Task.isCancelled { return }
                let due = point.time.timeIntervalSince(origin) / speed
                if due - lastEmitted < 0.25 { continue }
                let wait = due - Date.now.timeIntervalSince(began)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                onFix(CLLocation(
                    coordinate: point.coordinate, altitude: point.altitude, horizontalAccuracy: 5,
                    verticalAccuracy: 5, timestamp: .now))
                lastEmitted = due
            }
        }
    }

    func stop() {
        task?.cancel()
    }

    private struct Point: Sendable {
        let time: Date
        let coordinate: CLLocationCoordinate2D
        let altitude: Double
    }

    private nonisolated static func parse(path: String) -> [Point] {
        guard let text = try? String(contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8) else {
            return []
        }
        let formatter = ISO8601DateFormatter()
        func value(of tag: String, in chunk: Substring) -> String? {
            guard let open = chunk.range(of: "<\(tag)>"), let close = chunk.range(of: "</\(tag)>"),
                  open.upperBound <= close.lowerBound else { return nil }
            return String(chunk[open.upperBound..<close.lowerBound])
        }
        func attribute(_ name: String, in chunk: Substring) -> Double? {
            guard let open = chunk.range(of: "\(name)=\""),
                  let close = chunk[open.upperBound...].firstIndex(of: "\"") else { return nil }
            return Double(chunk[open.upperBound..<close])
        }
        var points: [Point] = []
        for chunk in text.split(separator: "<trkpt").dropFirst() {
            guard let lat = attribute("lat", in: chunk), let lon = attribute("lon", in: chunk),
                  let time = value(of: "time", in: chunk).flatMap({ formatter.date(from: $0) }) else { continue }
            let altitude = value(of: "ele", in: chunk).flatMap(Double.init) ?? 0
            points.append(Point(time: time, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude: altitude))
        }
        return points
    }
}
#endif
