#if targetEnvironment(simulator)
import CoreLocation
import TrainingWatchKit

/// Plays a GPX track as GPS fixes and heart rate in simulator builds, which otherwise get neither.
///
/// The simulator shares the Mac's file system, so the app reads the file directly, with no
/// location permission and no `simctl location`. The file is the `gpxPath` default (launch
/// argument `-gpxPath /path/track.gpx`) or else the first `.gpx` file in
/// `~/Documents/TrainingWatchGPX/`. The track plays at its real speed; `gpxSpeed`
/// (default 1) speeds it up when asked, and `gpxStartMinute` (default 0) skips the first part of
/// it. Each fix comes with the track's heart rate at that point when the file has one. The replay
/// stops while the run is paused, so the track doesn't run ahead of the workout's clock.
/// Never commit a GPX file: it holds real locations.
@MainActor
final class GPXReplay {
    private var task: Task<Void, Never>?
    private var began = Date.now
    private var pausedSince: Date?
    private var pausedTotal: TimeInterval = 0

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
    ///   - onLoaded: Called once the file is read, with whether its points carry heart rate. A file
    ///     that can't be read counts as one without, so the caller can fall back.
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
        pausedSince = nil
        pausedTotal = 0
        task = Task {
            // A track is thousands of points; parse it off the main actor.
            let track = await Task.detached {
                (try? String(contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8))
                    .map(GPXTrack.points(in:)) ?? []
            }.value
            guard !Task.isCancelled else { return }
            guard let first = track.first else {
                onLoaded(false)
                onError("no GPX points at \(path)")
                return
            }
            onLoaded(track.contains { $0.heartRate != nil })
            let origin = first.time.addingTimeInterval(startMinute * 60)
            began = .now
            var lastEmitted = -1.0
            for point in track where point.time >= origin {
                let due = point.time.timeIntervalSince(origin) / speed
                if due - lastEmitted < 0.25 { continue }
                // Wait until the track's clock reaches this point; the clock stands still while paused.
                while !Task.isCancelled {
                    let wait = pausedSince == nil ? due - elapsed() : 0.1
                    if wait <= 0 { break }
                    try? await Task.sleep(for: .seconds(min(wait, 0.1)))
                }
                if Task.isCancelled { return }
                onFix(
                    CLLocation(
                        coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                        altitude: point.altitude, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: .now),
                    point.heartRate)
                lastEmitted = due
            }
        }
    }

    /// How far the track's clock has run: real time since it started, less the time spent paused.
    private func elapsed() -> TimeInterval {
        let paused = pausedTotal + (pausedSince.map { Date.now.timeIntervalSince($0) } ?? 0)
        return Date.now.timeIntervalSince(began) - paused
    }

    /// Holds the track's clock, as pausing the run does.
    func pause() {
        if pausedSince == nil { pausedSince = .now }
    }

    /// Lets the track's clock run again.
    func resume() {
        guard let pausedSince else { return }
        pausedTotal += Date.now.timeIntervalSince(pausedSince)
        self.pausedSince = nil
    }

    func stop() {
        task?.cancel()
    }
}
#endif
