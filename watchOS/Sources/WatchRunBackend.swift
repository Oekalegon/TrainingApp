import CoreLocation
import HealthKit
import TrainingWatchKit
import WatchKit

/// The real ``RunBackend``: HealthKit, CoreLocation, the wrist and the battery. In the simulator,
/// which records no location or heart rate, a GPX replay (`GPXReplay`) or a made-up heart rate
/// stands in for them.
@MainActor
final class WatchRunBackend: RunBackend {
    private let store = HKHealthStore()
    private let locationFeed = LocationFeed()

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

    func requestHealthAuthorization() async throws -> Bool {
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
        return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    func makeWorkout() throws -> (session: any RunWorkoutSession, builder: any RunWorkoutBuilder) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
        return (
            HealthKitRunSession(session: session),
            HealthKitRunBuilder(
                store: store, configuration: configuration, session: session,
                reportsReadings: !suppliesSensorReadings))
    }

    /// Plays `cue` on the channels `CueRouting` picks: the wrist, the earbuds, or both. The channel
    /// is read now, so earbuds put in or taken out mid-run change it.
    func play(_ cue: RunCue) {
        let route = CueRouting.route(
            cue, headphonesConnected: audio.headphonesConnected, style: AudioCueStyle.stored())
        if route.haptic { playHaptic(cue) }
        if let sound = route.sound { audio.play(sound) }
    }

    private func playHaptic(_ cue: RunCue) {
        switch cue {
        case .zoneAlert(let alert): ZoneAlertHaptics.play(alert)
        case .goalReached: WKInterfaceDevice.current().play(.success)
        case .lapMarked: WKInterfaceDevice.current().play(.click)
        case .stepAnnouncement: break
        case .batteryWarning(let level):
            switch level {
            case .tight: WKInterfaceDevice.current().play(.notification)
            case .critical: WKInterfaceDevice.current().play(.retry)
            case .runsOut: WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    private let audio = CueAudioPlayer()

    func cancelPendingCues() {
        ZoneAlertHaptics.cancelPending()
        audio.cancel()
    }

    func battery(elapsed: TimeInterval) -> BatteryDisplay { BatteryReader.current(elapsed: elapsed) }

    #if targetEnvironment(simulator)
    private let replay = GPXReplay()
    private var simulatedHeartRateTask: Task<Void, Never>?
    private var replayFixCount = 0
    private var replayError: String?

    private var isReplayingGPX: Bool { GPXReplay.fileToPlay != nil }

    var suppliesSensorReadings: Bool { true }

    func requestLocationAuthorization() async -> Bool {
        // A GPX replay needs no location permission.
        if !isReplayingGPX { await locationFeed.requestAuthorization() }
        return locationFeed.isAuthorized || isReplayingGPX
    }

    var locationDescription: String { isReplayingGPX ? "GPX replay" : locationFeed.authorizationDescription }

    var locationDiagnostics: String {
        if isReplayingGPX { return "received \(replayFixCount)" + (replayError.map { ", error \($0)" } ?? "") }
        return feedDiagnostics
    }

    /// Starts what a simulator can't record: the GPX's location and heart rate when a file is set
    /// up, otherwise the simulator's own location and a made-up heart rate. A GPX without heart
    /// rate, or one that can't be read, also gets the made-up one.
    func startSensors(onLocations: @escaping ([CLLocation]) -> Void, onHeartRate: @escaping (Double) -> Void) {
        guard let path = GPXReplay.fileToPlay else {
            locationFeed.onUpdate = onLocations
            locationFeed.start()
            startSimulatedHeartRate(onHeartRate)
            return
        }
        replayFixCount = 0
        replayError = nil
        replay.start(
            path: path,
            onLoaded: { [weak self] hasHeartRate in
                if !hasHeartRate { self?.startSimulatedHeartRate(onHeartRate) }
            },
            onFix: { [weak self] fix, heartRate in
                self?.replayFixCount += 1
                onLocations([fix])
                if let heartRate { onHeartRate(heartRate) }
            },
            onError: { [weak self] message in self?.replayError = message })
    }

    func pauseSensors() { replay.pause() }
    func resumeSensors() { replay.resume() }

    func stopSensors() {
        locationFeed.stop()
        replay.stop()
        simulatedHeartRateTask?.cancel()
    }

    /// A slow ramp from 90 to 170 bpm (60 s up, then back down) once a second, for a simulator run
    /// with no GPX heart rate to play. Made up, and not meant to look like a run.
    private func startSimulatedHeartRate(_ deliver: @escaping (Double) -> Void) {
        simulatedHeartRateTask?.cancel()
        simulatedHeartRateTask = Task {
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let position = Double(abs((tick % 120) - 60)) / 60
                deliver(170 - 80 * position)
                tick += 1
            }
        }
    }
    #else
    var suppliesSensorReadings: Bool { false }

    func requestLocationAuthorization() async -> Bool {
        await locationFeed.requestAuthorization()
        return locationFeed.isAuthorized
    }

    var locationDescription: String { locationFeed.authorizationDescription }
    var locationDiagnostics: String { feedDiagnostics }

    func startSensors(onLocations: @escaping ([CLLocation]) -> Void, onHeartRate: @escaping (Double) -> Void) {
        locationFeed.onUpdate = onLocations
        locationFeed.start()
    }

    func pauseSensors() {}
    func resumeSensors() {}
    func stopSensors() { locationFeed.stop() }
    #endif

    private var feedDiagnostics: String {
        "received \(locationFeed.receivedCount), dropped \(locationFeed.droppedCount)"
            + (locationFeed.lastError.map { ", error \($0)" } ?? "")
    }
}
