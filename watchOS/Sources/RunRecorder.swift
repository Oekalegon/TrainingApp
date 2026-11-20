import Foundation
import HealthKit
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

    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRate),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned)
    ]
    private static let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.heartRate),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned)
    ]

    func start() async {
        do {
            try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
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
            phase = .running
            #if targetEnvironment(simulator)
            startSimulatedHeartRate()
            #endif
        } catch {
            phase = .failed(error.localizedDescription)
        }
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
                try? await builder.addSamples([sample])
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
        guard let builder else { return }
        do {
            try await builder.endCollection(at: .now)
            _ = try await builder.finishWorkout()
            phase = .saved
        } catch {
            phase = .failed(error.localizedDescription)
        }
        session = nil
        self.builder = nil
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
            if let distance { distanceMeters = distance }
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
