#if targetEnvironment(simulator)
import CoreLocation

/// Plays a GPX track as GPS fixes in simulator builds, which otherwise get no location.
///
/// The simulator shares the Mac's file system, so the app reads the file directly, with no
/// location permission and no `simctl location`. The file is the `gpxPath` default (launch
/// argument `-gpxPath /path/track.gpx`) or else the first `.gpx` file in
/// `~/Documents/TrainingWatchGPX/`. The track plays at its real speed; `gpxSpeed`
/// (default 1) speeds it up when asked, and `gpxStartMinute` (default 0) skips the first part of
/// it. Each fix comes with the track's heart rate at that point when the file has one.
/// Never commit a GPX file: it holds real locations.
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

    /// Starts playing `path`.
    ///
    /// - Parameters:
    ///   - path: The GPX file.
    ///   - onLoaded: Called once the file is read, with whether its points carry heart rate.
    ///   - onFix: Called for each fix (stamped with the current time, as a real fix would be) with
    ///     the heart rate at that point, if the file has one.
    ///   - onError: Called when the file has no usable points.
    func start(
        path: String,
        onLoaded: @escaping (Bool) -> Void,
        onFix: @escaping (CLLocation, Double?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        let defaults = UserDefaults.standard
        let speed = defaults.double(forKey: "gpxSpeed") > 0 ? defaults.double(forKey: "gpxSpeed") : 1
        let startMinute = defaults.double(forKey: "gpxStartMinute")
        task?.cancel()
        task = Task {
            // A track is thousands of points; parse it off the main actor.
            let track = await Task.detached { Self.parse(path: path) }.value
            guard let first = track.first else {
                onError("no GPX points at \(path)")
                return
            }
            onLoaded(track.contains { $0.heartRate != nil })
            let origin = first.time.addingTimeInterval(startMinute * 60)
            let began = Date.now
            var lastEmitted = -1.0
            for point in track where point.time >= origin {
                if Task.isCancelled { return }
                let due = point.time.timeIntervalSince(origin) / speed
                if due - lastEmitted < 0.25 { continue }
                let wait = due - Date.now.timeIntervalSince(began)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                onFix(
                    CLLocation(
                        coordinate: point.coordinate, altitude: point.altitude, horizontalAccuracy: 5,
                        verticalAccuracy: 5, timestamp: .now),
                    point.heartRate)
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
        /// In beats per minute, when the file has it.
        let heartRate: Double?
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
        /// The heart rate in a track point's extensions: `<gpxtpx:hr>` (Garmin's track point
        /// extension, whatever prefix the file gives it) or a plain `<hr>`.
        func heartRate(in chunk: Substring) -> Double? {
            guard let open = chunk.range(of: ":hr>") ?? chunk.range(of: "<hr>"),
                  let close = chunk[open.upperBound...].range(of: "</") else { return nil }
            return Double(chunk[open.upperBound..<close.lowerBound])
        }
        var points: [Point] = []
        for chunk in text.split(separator: "<trkpt").dropFirst() {
            guard let lat = attribute("lat", in: chunk), let lon = attribute("lon", in: chunk),
                  let time = value(of: "time", in: chunk).flatMap({ formatter.date(from: $0) }) else { continue }
            let altitude = value(of: "ele", in: chunk).flatMap(Double.init) ?? 0
            points.append(Point(
                time: time, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                altitude: altitude, heartRate: heartRate(in: chunk)))
        }
        return points
    }
}
#endif
