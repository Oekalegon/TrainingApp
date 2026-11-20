import Foundation
import CoreLocation
import HealthKit
import OSLog
import Observation

/// Records an outdoor run with an `HKWorkoutSession` and an `HKLiveWorkoutBuilder`, so the run is
/// saved to Health as a normal `HKWorkout` (WATCH-101). It shows the live heart rate and elapsed
/// time and nothing else yet: zones, steps and alerts come in later todos.
@MainActor
@Observable
final class RunRecorder: NSObject {
    enum Phase: Equatable {
        case idle
        case running
        case paused
        case saved
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// The latest heart rate in beats per minute.
    private(set) var heartRate: Double?
    private(set) var distanceMeters: Double = 0
    private(set) var startDate: Date?
    private(set) var elapsedOffset: TimeInterval = 0

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let locationFeed = LocationFeed()
    private(set) var routePointCount = 0
    private let log = Logger(subsystem: "org.oekalegon.trainingapp.watchkitapp", category: "RunRecorder")

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

    func start() async {
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
            await locationFeed.requestAuthorization()
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
            startDate = start
            lastDistanceSampleEnd = start
            phase = .running
            routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
            routePointCount = 0
            locationFeed.onUpdate = { [weak self] locations in
                Task { await self?.handle(locations) }
            }
            locationFeed.start()
            #if targetEnvironment(simulator)
            startSimulatedHeartRate()
            #endif
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Returns to the start screen after a finished or failed run.
    func reset() {
        guard phase == .saved || isFailed else { return }
        heartRate = nil
        distanceMeters = 0
        routePointCount = 0
        phase = .idle
    }

    /// The location permission, for the simulator's debug line.
    var locationDescription: String { locationFeed.authorizationDescription }

    /// Location counters and the last error, for the simulator's debug line.
    var locationDiagnostics: String {
        "received \(locationFeed.receivedCount), dropped \(locationFeed.droppedCount)"
            + (locationFeed.lastError.map { ", error \($0)" } ?? "")
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    func end() {
        session?.end()
    }

    /// Elapsed workout time at `date`, from the builder so paused time is excluded.
    func elapsed(at date: Date = .now) -> TimeInterval {
        builder?.elapsedTime(at: date) ?? 0
    }

    private var lastLocation: CLLocation?
    private var lastDistanceSampleEnd = Date.now

    private func handle(_ locations: [CLLocation]) async {
        guard phase == .running else { return }
        do { try await routeBuilder?.insertRouteData(locations) } catch { log.error("route insert failed: \(error.localizedDescription, privacy: .public)") }
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
        do { try await builder.addSamples([sample]) } catch { log.error("distance sample rejected: \(error.localizedDescription, privacy: .public)") }
        #endif
    }

    #if targetEnvironment(simulator)
    private var simulatedHeartRateTask: Task<Void, Never>?

    /// The simulator records no heart rate, so feed the builder a slow ramp from 90 to 170 bpm
    /// (60 s up, then back down) once a second. Only compiled for the simulator.
    private func startSimulatedHeartRate() {
        simulatedHeartRateTask?.cancel()
        simulatedHeartRateTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let builder = self.builder, self.phase == .running else { continue }
                let position = Double(abs((tick % 120) - 60)) / 60
                let bpm = 170 - 80 * position
                let unit = HKUnit.count().unitDivided(by: .minute())
                let sample = HKQuantitySample(
                    type: HKQuantityType(.heartRate),
                    quantity: HKQuantity(unit: unit, doubleValue: bpm),
                    start: .now, end: .now)
                do { try await builder.addSamples([sample]) } catch { self.log.error("heart-rate sample rejected: \(error.localizedDescription, privacy: .public)") }
                self.heartRate = bpm
                tick += 1
            }
        }
    }
    #endif

    private func finish() async {
        #if targetEnvironment(simulator)
        simulatedHeartRateTask?.cancel()
        #endif
        locationFeed.stop()
        guard let builder else { return }
        do {
            try await builder.endCollection(at: .now)
            let workout = try await builder.finishWorkout()
            if let workout, let routeBuilder, routePointCount > 0 {
                try await routeBuilder.finishRoute(with: workout, metadata: nil)
            }
            log.info("saved workout: \(self.distanceMeters, privacy: .public) m, \(self.routePointCount, privacy: .public) route points")
            phase = .saved
        } catch {
            phase = .failed(error.localizedDescription)
        }
        session = nil
        self.builder = nil
        routeBuilder = nil
        lastLocation = nil
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
            case .running: phase = .running
            case .paused: phase = .paused
            case .ended: await finish()
            default: break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in phase = .failed(message) }
    }
}

extension RunRecorder: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let bpm = Self.mostRecentHeartRate(in: workoutBuilder, collectedTypes: collectedTypes)
        let distance = Self.totalDistance(in: workoutBuilder, collectedTypes: collectedTypes)
        Task { @MainActor in
            if let bpm { heartRate = bpm }
            #if !targetEnvironment(simulator)
            // In the simulator the builder's own distance statistic stays near zero, so the screen
            // shows the sum of the replayed fixes instead (see `handle(_:)`).
            if let distance { distanceMeters = distance }
            #endif
        }
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
