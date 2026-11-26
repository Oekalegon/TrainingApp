import CoreLocation
import HealthKit
import OSLog
import TrainingWatchKit

/// An `HKWorkoutSession` behind ``RunWorkoutSession``.
@MainActor
final class HealthKitRunSession: NSObject, RunWorkoutSession {
    var onStateChange: ((RunSessionState) -> Void)?
    var onFailure: ((String) -> Void)?
    let session: HKWorkoutSession

    init(session: HKWorkoutSession) {
        self.session = session
        super.init()
        session.delegate = self
    }

    func start(at date: Date) { session.startActivity(with: date) }
    func pause() { session.pause() }
    func resume() { session.resume() }
    func end() { session.end() }
}

extension HealthKitRunSession: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let state: RunSessionState = switch toState {
        case .running: .running
        case .paused: .paused
        case .ended: .ended
        default: .other
        }
        Task { @MainActor in onStateChange?(state) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in onFailure?(message) }
    }
}

/// Why a route couldn't be saved.
private enum RouteError: Error { case noWorkout }

/// An `HKLiveWorkoutBuilder` and an `HKWorkoutRouteBuilder` behind ``RunWorkoutBuilder``.
@MainActor
final class HealthKitRunBuilder: NSObject, RunWorkoutBuilder {
    var onHeartRate: ((Double) -> Void)?
    var onDistance: ((Double) -> Void)?
    var onQuantity: ((RunQuantity, Double) -> Void)?
    /// The cadence from the step count's total over the last seconds (WATCH-135).
    private var cadence = CadenceEstimator()
    /// The readings beside heart rate, distance and energy that the run screens can show (WATCH-135). The live data
    /// source collects and saves them as the app, so the app must be allowed to share them as well as read them
    /// (`WatchRunBackend`), and each is enabled by name rather than left to the data source's own choice.
    static let extraTypes: [HKQuantityType] = [
        HKQuantityType(.stepCount), HKQuantityType(.runningSpeed), HKQuantityType(.runningStrideLength),
        HKQuantityType(.runningGroundContactTime), HKQuantityType(.runningVerticalOscillation), HKQuantityType(.runningPower),
    ]
    private let builder: HKLiveWorkoutBuilder
    private let routeBuilder: HKWorkoutRouteBuilder
    private var workout: HKWorkout?
    /// Whether the builder's own readings are shown: not in the simulator, where they aren't the
    /// replay's (a 134 bpm appeared that is nowhere in the GPX) and the distance stays near zero.
    private let reportsReadings: Bool

    init(store: HKHealthStore, configuration: HKWorkoutConfiguration, session: HKWorkoutSession, reportsReadings: Bool) {
        builder = session.associatedWorkoutBuilder()
        let dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
        for type in Self.extraTypes { dataSource.enableCollection(for: type, predicate: nil) }
        builder.dataSource = dataSource
        routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        self.reportsReadings = reportsReadings
        // The delegate is set after `super.init()`, which `self` needs.
        super.init()
        builder.delegate = self
    }

    func elapsedTime(at date: Date) -> TimeInterval { builder.elapsedTime(at: date) }
    func beginCollection(at date: Date) async throws { try await builder.beginCollection(at: date) }
    func endCollection(at date: Date) async throws { try await builder.endCollection(at: date) }
    func finishWorkout() async throws { workout = try await builder.finishWorkout() }
    func addMetadata(_ metadata: [String: Any]) async throws { try await builder.addMetadata(metadata) }

    func addEvents(_ events: [RunEvent]) async throws {
        try await builder.addWorkoutEvents(events.map { event in
            HKWorkoutEvent(
                type: event.kind == .lap ? .lap : .segment,
                dateInterval: DateInterval(start: event.start, end: event.end), metadata: event.metadata)
        })
    }

    func addDistanceSample(meters: Double, from start: Date, to end: Date) async throws {
        try await builder.addSamples([HKQuantitySample(
            type: HKQuantityType(.distanceWalkingRunning),
            quantity: HKQuantity(unit: .meter(), doubleValue: meters), start: start, end: end)])
    }

    func addHeartRateSample(_ bpm: Double, at date: Date) async throws {
        try await builder.addSamples([HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: bpm),
            start: date, end: date)])
    }

    func insertRoute(_ locations: [CLLocation]) async throws { try await routeBuilder.insertRouteData(locations) }

    func finishRoute() async throws {
        guard let workout else { throw RouteError.noWorkout }
        try await routeBuilder.finishRoute(with: workout, metadata: nil)
    }

    func discard() {
        builder.discardWorkout()
        routeBuilder.discard()
    }
}

extension HealthKitRunBuilder: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let heartRateType = HKQuantityType(.heartRate)
        let distanceType = HKQuantityType(.distanceWalkingRunning)
        let bpm = collectedTypes.contains(heartRateType)
            ? workoutBuilder.statistics(for: heartRateType)?.mostRecentQuantity()?
                .doubleValue(for: .count().unitDivided(by: .minute()))
            : nil
        let distance = collectedTypes.contains(distanceType)
            ? workoutBuilder.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter())
            : nil
        // The other readings of the workout (WATCH-135): the latest value of each type that arrived, in the
        // unit the quantity is shown from. Types a watch doesn't measure never arrive.
        var readings: [(RunQuantity, Double)] = []
        func latest(_ identifier: HKQuantityTypeIdentifier, _ unit: HKUnit) -> Double? {
            let type = HKQuantityType(identifier)
            guard collectedTypes.contains(type) else { return nil }
            return workoutBuilder.statistics(for: type)?.mostRecentQuantity()?.doubleValue(for: unit)
        }
        if let value = latest(.runningSpeed, .meter().unitDivided(by: .second())) { readings.append((.runningSpeed, value)) }
        if let value = latest(.runningStrideLength, .meter()) { readings.append((.strideLength, value)) }
        if let value = latest(.runningGroundContactTime, .secondUnit(with: .milli)) { readings.append((.groundContactTime, value)) }
        if let value = latest(.runningVerticalOscillation, .meterUnit(with: .centi)) { readings.append((.verticalOscillation, value)) }
        if let value = latest(.runningPower, .watt()) { readings.append((.runningPower, value)) }
        let stepType = HKQuantityType(.stepCount)
        let steps = collectedTypes.contains(stepType)
            ? workoutBuilder.statistics(for: stepType)?.sumQuantity()?.doubleValue(for: .count())
            : nil
        let elapsed = workoutBuilder.elapsedTime
        Task { @MainActor in
            guard reportsReadings else { return }
            if let bpm { onHeartRate?(bpm) }
            if let distance { onDistance?(distance) }
            for (quantity, value) in readings { onQuantity?(quantity, value) }
            if let steps, let spm = cadence.add(totalSteps: steps, atElapsed: elapsed) { onQuantity?(.cadence, spm) }
        }
    }
}
