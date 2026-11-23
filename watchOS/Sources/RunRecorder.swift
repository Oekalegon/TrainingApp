import CoreLocation
import Foundation
import HealthKit
import OSLog
import Observation
import TrainingWatchKit

/// Records an outdoor run with an `HKWorkoutSession` and an `HKLiveWorkoutBuilder`, so the run is
/// saved to Health as a normal `HKWorkout` (WATCH-101). It shows the live heart rate and elapsed
/// time and nothing else yet: zones, steps and alerts come in later todos.
@MainActor
@Observable
final class RunRecorder: NSObject {
    enum Phase: Equatable {
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

    private(set) var phase: Phase = .idle
    /// The latest heart rate in beats per minute.
    private(set) var heartRate: Double?
    private(set) var distanceMeters: Double = 0
    /// The steps of the planned workout being run, or `nil` in a free run. Set and changed by
    /// `RunRecorder+Steps.swift`; views only read it.
    var stepEngine: WorkoutStepEngine?
    /// The athlete's zones, to turn a step's heart-rate target into bpm for the alerts. Set by the app.
    var zoneStore: WatchZoneStore?
    /// Decides when the heart rate against the step's target is worth an alert (WATCH-106). Used by
    /// `RunRecorder+Alerts.swift`.
    var alertEngine = ZoneAlertEngine()
    /// How many segment and lap events have been written to the workout, for the simulator's debug line.
    var eventsWritten = 0
    /// When the current step began, for its segment event. Set by `RunRecorder+Steps.swift`.
    var stepStartDate = Date.now
    /// Watches the clock and the distance for the end of a step. Set by `RunRecorder+Steps.swift`.
    var stepTicker: Task<Void, Never>?
    /// Events that couldn't be written yet. Set by `RunRecorder+Steps.swift`.
    var pendingEvents: [HKWorkoutEvent] = []
    /// After a failed save: the recorded run is still held, so it can be saved again or discarded.
    private(set) var canRetrySave = false
    /// Set when a run was saved without its route (no location permission, or the route failed),
    /// so the end screen can say so.
    private(set) var routeNote: String?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    // Internal, not private, because `RunRecorder+Steps.swift` extends this type.
    var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let locationFeed = LocationFeed()
    private(set) var routePointCount = 0
    let log = Logger(subsystem: "org.oekalegon.trainingapp.watchkitapp", category: "RunRecorder")

    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRate),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned)
    ]
    private static let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKSeriesType.workoutRoute(),
        HKQuantityType(.heartRate),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned)
    ]

    /// Set while a failed start or run is being torn down, so the session's `.ended` callback
    /// doesn't try to finish a workout that is being thrown away.
    private var abandoned = false

    /// Starts a run.
    ///
    /// - Parameter plan: A planned workout to run the steps of and to tag the saved workout with;
    ///   `nil` for a free run.
    func start(plan: WatchPlannedWorkout? = nil) async {
        guard phase == .idle else { return }
        phase = .starting
        abandoned = false
        routeNote = nil
        locationAllowedAtStart = false
        do {
            // A no-op once the user has answered. HealthKit never shows the sheet a second time,
            // so a denied answer has to be fixed in the Health settings.
            try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
            guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
                phase = .failed("Workouts can't be saved to Health. On your iPhone, open Health, tap your profile, Apps, TrainingWatch and turn on Workouts, then try again.")
                return
            }
            // Ask for location now, before the run, so its prompt isn't shown over the workout. A
            // "no" still records the run, just without a route and (on a real watch) less distance.
            #if targetEnvironment(simulator)
            // A GPX replay needs no location permission.
            if !isReplayingGPX { await locationFeed.requestAuthorization() }
            locationAllowedAtStart = locationFeed.isAuthorized || isReplayingGPX
            #else
            await locationFeed.requestAuthorization()
            locationAllowedAtStart = locationFeed.isAuthorized
            #endif
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .running
            configuration.locationType = .outdoor
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            lastDistanceSampleEnd = start
            phase = .running
            if let plan { await beginSteps(for: plan, at: start) }
            routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
            routePointCount = 0
            locationFeed.onUpdate = { [weak self] locations in
                Task { await self?.handle(locations) }
            }
            #if targetEnvironment(simulator)
            startSimulatedSensors()
            #else
            locationFeed.start()
            #endif
        } catch {
            teardown()
            phase = .failed(error.localizedDescription)
        }
    }

    /// Stops everything a run started and throws the unsaved workout away: the session, the
    /// builder, the route, the location updates and the simulator's heart-rate feed. Used when a
    /// start or the session fails, so nothing keeps recording or draining the battery.
    private func teardown() {
        abandoned = true
        stopLocation()
        session?.end()
        builder?.discardWorkout()
        routeBuilder?.discard()
        releaseRun()
    }

    /// Stops the GPS and the step clock (and, in the simulator, the replay and its heart rate).
    private func stopLocation() {
        stepTicker?.cancel()
        locationFeed.stop()
        #if targetEnvironment(simulator)
        replay.stop()
        simulatedHeartRateTask?.cancel()
        #endif
    }

    private func releaseRun() {
        stepEngine = nil
        stepTicker = nil
        pendingEvents = []
        session = nil
        builder = nil
        routeBuilder = nil
        lastLocation = nil
        canRetrySave = false
        collectionEnded = false
    }

    private var locationAllowedAtStart = false
    private var collectionEnded = false

    /// Returns to the start screen after a finished or failed run.
    func reset() {
        guard phase == .saved || isFailed else { return }
        if canRetrySave {
            // Discarding a run that couldn't be saved.
            builder?.discardWorkout()
            routeBuilder?.discard()
            releaseRun()
        }
        heartRate = nil
        distanceMeters = 0
        routePointCount = 0
        phase = .idle
    }

    /// The location permission, for the simulator's debug line.
    var locationDescription: String {
        #if targetEnvironment(simulator)
        if isReplayingGPX { return "GPX replay" }
        #endif
        return locationFeed.authorizationDescription
    }

    /// Location counters and the last error, for the simulator's debug line.
    var locationDiagnostics: String {
        #if targetEnvironment(simulator)
        if isReplayingGPX { return "received \(replayFixCount)" + (replayError.map { ", error \($0)" } ?? "") }
        #endif
        return "received \(locationFeed.receivedCount), dropped \(locationFeed.droppedCount)"
            + (locationFeed.lastError.map { ", error \($0)" } ?? "")
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    func pause() {
        guard phase == .running else { return }
        alertEngine.pause()
        session?.pause()
    }
    func resume() {
        guard phase == .paused else { return }
        // Fixes are ignored while paused, so measure the next one from nothing, not from the
        // position before the pause.
        lastLocation = nil
        session?.resume()
    }

    func end() {
        guard phase == .running || phase == .paused else { return }
        session?.end()
    }

    /// Elapsed workout time at `date`, from the builder so paused time is excluded.
    func elapsed(at date: Date = .now) -> TimeInterval {
        builder?.elapsedTime(at: date) ?? 0
    }

    private var lastLocation: CLLocation?
    private var lastDistanceSampleEnd = Date.now

    /// Sends a batch of GPS fixes to the route builder and, in simulator builds, turns them into
    /// distance. Ignored while paused, so the route has no points from the pause.
    private func handle(_ locations: [CLLocation]) async {
        guard phase == .running else { return }
        do {
            try await routeBuilder?.insertRouteData(locations)
        } catch {
            log.error("route insert failed: \(error.localizedDescription, privacy: .public)")
        }
        routePointCount += locations.count
        #if targetEnvironment(simulator)
        // The simulator records no distance from GPS, so derive it from the playback locations.
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
        let sample = HKQuantitySample(
            type: HKQuantityType(.distanceWalkingRunning),
            quantity: HKQuantity(unit: .meter(), doubleValue: batchMeters),
            start: lastDistanceSampleEnd, end: end)
        lastDistanceSampleEnd = end
        do {
            try await builder.addSamples([sample])
        } catch {
            log.error("distance sample rejected: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    #if targetEnvironment(simulator)
    private var simulatedHeartRateTask: Task<Void, Never>?
    private let replay = GPXReplay()
    /// How many fixes the GPX replay has played, for the simulator's debug line.
    private(set) var replayFixCount = 0
    private var replayError: String?

    /// Whether the simulator is playing a GPX file instead of using CoreLocation.
    private var isReplayingGPX: Bool { GPXReplay.fileToPlay != nil }

    /// Starts what a simulator can't record: the GPX's location and heart rate when a file is set
    /// up (`GPXReplay`), otherwise the simulator's own location and a made-up heart rate. A GPX
    /// without heart rate, or one that can't be read, also gets the made-up one.
    private func startSimulatedSensors() {
        guard let path = GPXReplay.fileToPlay else {
            locationFeed.start()
            startSimulatedHeartRate()
            return
        }
        replayFixCount = 0
        replayError = nil
        replay.start(
            path: path,
            onLoaded: { [weak self] hasHeartRate in
                // The file is read in the background; a run that has ended meanwhile needs nothing.
                guard let self, phase == .running || phase == .paused, !hasHeartRate else { return }
                startSimulatedHeartRate()
            },
            onFix: { [weak self] fix, heartRate in
                self?.replayFixCount += 1
                Task { await self?.handle([fix]) }
                if let heartRate { Task { await self?.recordSimulatedHeartRate(heartRate) } }
            },
            onError: { [weak self] message in self?.replayError = message })
    }

    /// Gives the builder a heart rate reading and shows it, as a real watch's sensor would. Only
    /// while running, and only compiled for the simulator, which records none.
    private func recordSimulatedHeartRate(_ bpm: Double) async {
        guard phase == .running, let builder else { return }
        // Shown before the await, so readings land in the order they were taken and one still in
        // flight when the run ends can't show up on the next run.
        heartRate = bpm
        alertHeartRate(bpm)
        let sample = HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: bpm),
            start: .now, end: .now)
        do {
            try await builder.addSamples([sample])
        } catch {
            log.error("heart-rate sample rejected: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A slow ramp from 90 to 170 bpm (60 s up, then back down) once a second, for a simulator run
    /// with no GPX heart rate to play. Made up, and not meant to look like a run.
    private func startSimulatedHeartRate() {
        simulatedHeartRateTask?.cancel()
        simulatedHeartRateTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                let position = Double(abs((tick % 120) - 60)) / 60
                await self.recordSimulatedHeartRate(170 - 80 * position)
                tick += 1
            }
        }
    }
    #endif

    /// Ends the workout and saves it, then the route. A failed save keeps the recorded run so it
    /// can be tried again (`retrySave()`); a failed route doesn't make the saved run a failure.
    private func finish() async {
        stopLocation()
        guard let builder else { return }
        phase = .saving
        await closeCurrentStep()
        await flushPendingEvents()
        let workout: HKWorkout?
        do {
            if !collectionEnded {
                try await builder.endCollection(at: .now)
                collectionEnded = true
            }
            workout = try await builder.finishWorkout()
        } catch {
            canRetrySave = true
            phase = .failed("The run couldn't be saved: \(error.localizedDescription)")
            return
        }
        if !locationAllowedAtStart {
            routeNote = "No route recorded: location is off for TrainingWatch."
        } else if let workout, let routeBuilder, routePointCount > 0 {
            do {
                try await routeBuilder.finishRoute(with: workout, metadata: nil)
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
    func retrySave() async {
        guard canRetrySave else { return }
        canRetrySave = false
        await finish()
    }
}

extension RunRecorder: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running:
                phase = .running
                #if targetEnvironment(simulator)
                replay.resume()
                #endif
            case .paused:
                phase = .paused
                #if targetEnvironment(simulator)
                replay.pause()
                #endif
            case .ended where !abandoned: await finish()
            default: break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            teardown()
            phase = .failed(message)
        }
    }
}

extension RunRecorder: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        #if !targetEnvironment(simulator)
        // In the simulator the builder's own readings aren't the replay's (a 134 bpm appeared that
        // is nowhere in the GPX) and its distance statistic stays near zero, so the screen shows
        // only what the replay supplies (see `recordSimulatedHeartRate(_:)` and `handle(_:)`).
        let bpm = Self.mostRecentHeartRate(in: workoutBuilder, collectedTypes: collectedTypes)
        let distance = Self.totalDistance(in: workoutBuilder, collectedTypes: collectedTypes)
        Task { @MainActor in
            if let bpm {
                heartRate = bpm
                alertHeartRate(bpm)
            }
            if let distance { distanceMeters = distance }
        }
        #endif
    }

    private nonisolated static func mostRecentHeartRate(
        in builder: HKLiveWorkoutBuilder, collectedTypes: Set<HKSampleType>
    ) -> Double? {
        let type = HKQuantityType(.heartRate)
        guard collectedTypes.contains(type) else { return nil }
        return builder.statistics(for: type)?.mostRecentQuantity()?
            .doubleValue(for: .count().unitDivided(by: .minute()))
    }

    private nonisolated static func totalDistance(
        in builder: HKLiveWorkoutBuilder, collectedTypes: Set<HKSampleType>
    ) -> Double? {
        let type = HKQuantityType(.distanceWalkingRunning)
        guard collectedTypes.contains(type) else { return nil }
        return builder.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter())
    }
}
