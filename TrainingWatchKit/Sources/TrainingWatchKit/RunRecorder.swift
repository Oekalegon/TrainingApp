import CoreLocation
import Foundation
import OSLog
import Observation

/// Records an outdoor run, so it is saved to Health as a normal workout (WATCH-101). It shows the
/// live heart rate and elapsed time, runs a planned workout's steps (`RunRecorder+Steps.swift`) and
/// plays the zone alerts (`RunRecorder+Alerts.swift`) and the battery warnings
/// (`RunRecorder+Battery.swift`).
///
/// Everything that touches the system (HealthKit, GPS, haptics, the battery) is behind a
/// ``RunBackend``, so the phases and the sums can be tested (WATCH-113).
@MainActor
@Observable
public final class RunRecorder {
    public enum Phase: Equatable {
        case idle
        /// Asking for permissions and starting the session; a second Start is ignored.
        case starting
        case running
        case paused
        /// Ending the session and saving the workout; if it fails, `canRetrySave` says whether the
        /// recorded data is still there to save again.
        case saving
        case saved
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    /// The latest heart rate in beats per minute.
    public private(set) var heartRate: Double?
    public private(set) var distanceMeters: Double = 0
    /// The steps of the planned workout being run, or `nil` in a free run. Set and changed by
    /// `RunRecorder+Steps.swift`; views only read it.
    public var stepEngine: WorkoutStepEngine?
    /// The athlete's zones, to turn a step's heart-rate target into bpm for the alerts. Set by the app.
    public var zoneStore: WatchZoneStore?
    /// Decides when the heart rate against the step's target is worth an alert (WATCH-106). Used by
    /// `RunRecorder+Alerts.swift`.
    var alertEngine = ZoneAlertEngine(settings: .heartRate)
    /// The last few alerts with the run time they came at, newest last, for the simulator's debug
    /// line. Kept on a real watch too: it is three small entries. Set by `RunRecorder+Alerts.swift`.
    var alertLog: [(time: TimeInterval, alert: ZoneAlert)] = []
    /// The battery readings of a planned workout so far, for the forecast (WATCH-119). Set by
    /// `RunRecorder+Battery.swift`.
    public internal(set) var batteryReadings: [BatteryForecast.Reading] = []
    /// The temporary battery warning screen, or `nil` when none shows (WATCH-110). Set and cleared by
    /// `RunRecorder+Battery.swift`; the run view shows it.
    public internal(set) var batteryWarning: BatteryWarning?
    /// Decides when the battery is worth a warning. Used by `RunRecorder+Battery.swift`.
    var batteryWarningTracker = BatteryWarningTracker()
    /// Reads the battery during the run. Set by `RunRecorder+Battery.swift`.
    var batteryTicker: Task<Void, Never>?
    /// Taps the wrist again every half minute while a warning stays. Set by `RunRecorder+Battery.swift`.
    var warningNudge: Task<Void, Never>?
    /// How many segment and lap events have been written to the workout, for the simulator's debug line.
    public internal(set) var eventsWritten = 0
    /// When the current step began, for its segment event. Set by `RunRecorder+Steps.swift`.
    var stepStartDate = Date.now
    /// The step announced before it started (WATCH-107), so it isn't announced again as it starts.
    var announcedAheadIndex: Int?
    /// The last second of the countdown that was sounded (5 to 1), so each is sounded once.
    var lastCountdownSecond: Int?
    /// Watches the clock and the distance for the end of a step. Set by `RunRecorder+Steps.swift`.
    var stepTicker: Task<Void, Never>?
    /// Events that couldn't be written yet. Set by `RunRecorder+Steps.swift`.
    var pendingEvents: [RunEvent] = []
    /// After a failed save: the recorded run is still held, so it can be saved again or discarded.
    public private(set) var canRetrySave = false
    /// Set when a run was saved without its route (no location permission, or the route failed),
    /// so the end screen can say so.
    public private(set) var routeNote: String?

    let backend: any RunBackend
    private var session: (any RunWorkoutSession)?
    // Internal, not private, because `RunRecorder+Steps.swift` extends this type.
    var builder: (any RunWorkoutBuilder)?
    public private(set) var routePointCount = 0
    let log = Logger(subsystem: "org.oekalegon.trainingapp.watchkitapp", category: "RunRecorder")

    /// Set while a failed start or run is being torn down, so the session's `.ended` callback
    /// doesn't try to finish a workout that is being thrown away.
    private var abandoned = false
    private var locationAllowedAtStart = false
    private var collectionEnded = false
    private var lastLocation: CLLocation?
    private var lastDistanceSampleEnd = Date.now

    public init(backend: any RunBackend) {
        self.backend = backend
    }

    /// The location permission, for the simulator's debug line.
    public var locationDescription: String { backend.locationDescription }

    /// Location counters and the last error, for the simulator's debug line.
    public var locationDiagnostics: String { backend.locationDiagnostics }

    /// Starts a run.
    ///
    /// - Parameter plan: A planned workout to run the steps of and to tag the saved workout with;
    ///   `nil` for a free run.
    public func start(plan: WatchPlannedWorkout? = nil) async {
        guard phase == .idle else { return }
        phase = .starting
        abandoned = false
        routeNote = nil
        locationAllowedAtStart = false
        do {
            // A no-op once the user has answered. HealthKit never shows the sheet a second time,
            // so a denied answer has to be fixed in the Health settings.
            guard try await backend.requestHealthAuthorization() else {
                phase = .failed("Workouts can't be saved to Health. On your iPhone, open Health, tap your profile, Apps, TrainingWatch and turn on Workouts, then try again.")
                return
            }
            // Ask for location now, before the run, so its prompt isn't shown over the workout. A
            // "no" still records the run, just without a route and (on a real watch) less distance.
            locationAllowedAtStart = await backend.requestLocationAuthorization()
            let (session, builder) = try backend.makeWorkout()
            session.onStateChange = { [weak self] state in
                Task { @MainActor in await self?.sessionChanged(to: state) }
            }
            session.onFailure = { [weak self] message in
                Task { @MainActor in self?.sessionFailed(message) }
            }
            builder.onHeartRate = { [weak self] bpm in
                Task { @MainActor in self?.heartRateArrived(bpm) }
            }
            builder.onDistance = { [weak self] meters in
                Task { @MainActor in self?.distanceMeters = meters }
            }
            self.session = session
            self.builder = builder
            let start = Date()
            session.start(at: start)
            try await builder.beginCollection(at: start)
            lastDistanceSampleEnd = start
            phase = .running
            startBatteryWatch()
            if let plan { await beginSteps(for: plan, at: start) }
            routePointCount = 0
            backend.startSensors(
                onLocations: { [weak self] locations in
                    Task { @MainActor in await self?.handle(locations) }
                },
                onHeartRate: { [weak self] bpm in
                    Task { @MainActor in await self?.simulatedHeartRateArrived(bpm) }
                })
        } catch {
            teardown()
            phase = .failed(error.localizedDescription)
        }
    }

    /// Stops everything a run started and throws the unsaved workout away: the session, the
    /// builder, the route and the sensors. Used when a start or the session fails, so nothing keeps
    /// recording or draining the battery.
    private func teardown() {
        abandoned = true
        stopSensors()
        session?.end()
        builder?.discard()
        releaseRun()
    }

    /// Stops the GPS and the step clock (and, in the simulator, the replay and its heart rate).
    private func stopSensors() {
        stepTicker?.cancel()
        stopBatteryWatch()
        backend.stopSensors()
    }

    private func releaseRun() {
        stepEngine = nil
        stepTicker = nil
        pendingEvents = []
        session = nil
        builder = nil
        lastLocation = nil
        canRetrySave = false
        collectionEnded = false
    }

    /// Returns to the start screen after a finished or failed run.
    public func reset() {
        guard phase == .saved || isFailed else { return }
        if canRetrySave {
            // Discarding a run that couldn't be saved.
            builder?.discard()
            releaseRun()
        }
        heartRate = nil
        distanceMeters = 0
        routePointCount = 0
        alertLog = []
        phase = .idle
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    public func pause() {
        guard phase == .running else { return }
        session?.pause()
    }

    public func resume() {
        guard phase == .paused else { return }
        // Fixes are ignored while paused, so measure the next one from nothing, not from the
        // position before the pause.
        lastLocation = nil
        session?.resume()
    }

    public func end() {
        guard phase == .running || phase == .paused else { return }
        session?.end()
    }

    /// Elapsed workout time at `date`, from the builder so paused time is excluded.
    public func elapsed(at date: Date = .now) -> TimeInterval {
        builder?.elapsedTime(at: date) ?? 0
    }

    /// The session changed state, whoever caused it: the button or the system.
    func sessionChanged(to state: RunSessionState) async {
        switch state {
        case .running:
            phase = .running
            backend.resumeSensors()
        case .paused:
            phase = .paused
            alertEngine.pause()
            backend.pauseSensors()
        case .ended where !abandoned:
            await finish()
        default:
            break
        }
    }

    func sessionFailed(_ message: String) {
        teardown()
        phase = .failed(message)
    }

    /// A heart-rate reading from the builder.
    func heartRateArrived(_ bpm: Double) {
        heartRate = bpm
        alertHeartRate(bpm)
    }

    /// A heart-rate reading from a backend that supplies its own (the simulator): shows it and gives
    /// it to the builder, as a real watch's sensor would. Only while running.
    private func simulatedHeartRateArrived(_ bpm: Double) async {
        guard phase == .running, let builder else { return }
        // Shown before the await, so readings land in the order they were taken and one still in
        // flight when the run ends can't show up on the next run.
        heartRateArrived(bpm)
        do {
            try await builder.addHeartRateSample(bpm, at: .now)
        } catch {
            log.error("heart-rate sample rejected: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Sends a batch of GPS fixes to the route and, for a backend that supplies the sensors, turns
    /// them into distance. Ignored while paused, so the route has no points from the pause.
    func handle(_ locations: [CLLocation]) async {
        guard phase == .running else { return }
        do {
            try await builder?.insertRoute(locations)
        } catch {
            log.error("route insert failed: \(error.localizedDescription, privacy: .public)")
        }
        routePointCount += locations.count
        guard backend.suppliesSensorReadings else { return }
        // Such a backend records no distance from GPS, so derive it from the playback locations.
        // One sample per batch, stamped from the previous sample's end to now: a fix's own
        // timestamp can predate the builder's start, and HealthKit then puts the builder into an
        // error state that refuses to end collection or save the workout.
        var batchMeters = 0.0
        for location in locations {
            if let previous = lastLocation { batchMeters += location.distance(from: previous) }
            lastLocation = location
        }
        guard batchMeters > 0, let builder else { return }
        distanceMeters += batchMeters
        let end = max(Date.now, lastDistanceSampleEnd.addingTimeInterval(0.001))
        let sampleStart = lastDistanceSampleEnd
        lastDistanceSampleEnd = end
        do {
            try await builder.addDistanceSample(meters: batchMeters, from: sampleStart, to: end)
        } catch {
            log.error("distance sample rejected: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Ends the workout and saves it, then the route. A failed save keeps the recorded run so it
    /// can be tried again (`retrySave()`); a failed route doesn't make the saved run a failure.
    func finish() async {
        stopSensors()
        guard let builder else { return }
        phase = .saving
        await closeCurrentStep()
        await flushPendingEvents()
        do {
            if !collectionEnded {
                try await builder.endCollection(at: .now)
                collectionEnded = true
            }
            try await builder.finishWorkout()
        } catch {
            canRetrySave = true
            phase = .failed("The run couldn't be saved: \(error.localizedDescription)")
            return
        }
        if !locationAllowedAtStart {
            routeNote = "No route recorded: location is off for TrainingWatch."
        } else if routePointCount > 0 {
            do {
                try await builder.finishRoute()
            } catch {
                log.error("route not saved: \(error.localizedDescription, privacy: .public)")
                routeNote = "The route couldn't be saved."
            }
        }
        log.info("saved workout: \(self.distanceMeters, privacy: .public) m, \(self.routePointCount, privacy: .public) route points")
        phase = .saved
        releaseRun()
    }

    /// Tries again to save a run whose save failed.
    public func retrySave() async {
        guard canRetrySave else { return }
        canRetrySave = false
        await finish()
    }
}
