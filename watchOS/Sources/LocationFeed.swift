import CoreLocation

/// Streams GPS fixes for an outdoor run. `RunRecorder` forwards them to an `HKWorkoutRouteBuilder`
/// so the route is saved with the workout (WATCH-101).
@MainActor
final class LocationFeed: NSObject, CLLocationManagerDelegate {
    var onUpdate: (([CLLocation]) -> Void)?

    /// Counters for the simulator's debug line: fixes delivered, fixes dropped as too coarse or
    /// invalid, and the last error CoreLocation reported.
    private(set) var receivedCount = 0
    private(set) var droppedCount = 0
    private(set) var lastError: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
    }

    private var authorizationContinuation: CheckedContinuation<Void, Never>?

    var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    /// A short description of the permission, for the simulator's debug line.
    var authorizationDescription: String {
        #if targetEnvironment(simulator)
        if isReplayingGPX { return "GPX replay" }
        #endif
        return switch manager.authorizationStatus {
        case .notDetermined: "not asked"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorizedAlways, .authorizedWhenInUse: "allowed"
        @unknown default: "unknown"
        }
    }

    /// Asks for location access and returns once the user has answered, so the prompt comes before
    /// the run and not over it. Returns at once when it has already been answered.
    func requestAuthorization() async {
        #if targetEnvironment(simulator)
        if isReplayingGPX { return }
        #endif
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func start() {
        #if targetEnvironment(simulator)
        if let path = UserDefaults.standard.string(forKey: "gpxPath") {
            startReplay(of: path)
            return
        }
        #endif
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        #if targetEnvironment(simulator)
        replayTask?.cancel()
        #endif
    }

    #if targetEnvironment(simulator)
    private var replayTask: Task<Void, Never>?

    /// True when simulator builds play a GPX file instead of using CoreLocation.
    var isReplayingGPX: Bool { UserDefaults.standard.string(forKey: "gpxPath") != nil }

    /// Plays a GPX track into `onUpdate` as if the watch were running it (simulator only).
    ///
    /// Set the file once with `xcrun simctl spawn <UDID> defaults write
    /// org.oekalegon.trainingapp.watchkitapp gpxPath /path/to/track.gpx`, or pass
    /// `-gpxPath /path/to/track.gpx` as a launch argument in the scheme. `gpxSpeed` (default 10)
    /// speeds the track up and `gpxStartMinute` (default 0) skips the first part of it. The
    /// simulator shares the Mac's file system, so the app can read the file directly; this needs
    /// neither location permission nor `simctl location`.
    private func startReplay(of path: String) {
        let defaults = UserDefaults.standard
        let speed = max(defaults.double(forKey: "gpxSpeed"), 0) == 0 ? 10 : defaults.double(forKey: "gpxSpeed")
        let startMinute = defaults.double(forKey: "gpxStartMinute")
        replayTask?.cancel()
        replayTask = Task { [weak self] in
            let track = Self.parseGPX(at: path)
            guard let first = track.first else {
                self?.lastError = "no GPX points at \(path)"
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
                guard let self else { return }
                let fix = CLLocation(
                    coordinate: point.coordinate, altitude: point.altitude, horizontalAccuracy: 5,
                    verticalAccuracy: 5, timestamp: .now)
                self.receivedCount += 1
                self.onUpdate?([fix])
                lastEmitted = due
            }
        }
    }

    private nonisolated static func parseGPX(at path: String)
        -> [(time: Date, coordinate: CLLocationCoordinate2D, altitude: Double)] {
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
        var points: [(time: Date, coordinate: CLLocationCoordinate2D, altitude: Double)] = []
        for chunk in text.split(separator: "<trkpt").dropFirst() {
            guard let lat = attribute("lat", in: chunk), let lon = attribute("lon", in: chunk),
                  let time = value(of: "time", in: chunk).flatMap({ formatter.date(from: $0) }) else { continue }
            let altitude = value(of: "ele", in: chunk).flatMap(Double.init) ?? 0
            points.append((time, CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude))
        }
        return points
    }
    #endif

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Drop invalid fixes and very coarse ones.
        let usable = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }
        let total = locations.count
        Task { @MainActor in
            self.receivedCount += total
            self.droppedCount += total - usable.count
            if !usable.isEmpty { self.onUpdate?(usable) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.manager.authorizationStatus != .notDetermined else { return }
            self.authorizationContinuation?.resume()
            self.authorizationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let description = "CL \((error as NSError).code)"
        Task { @MainActor in self.lastError = description }
    }
}
