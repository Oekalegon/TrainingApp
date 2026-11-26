import CoreLocation
import Foundation
@testable import TrainingWatchKit

struct FakeFailure: Error, LocalizedError {
    var errorDescription: String? { "fake failure" }
}

@MainActor
final class FakeRunSession: RunWorkoutSession {
    var onStateChange: ((RunSessionState) -> Void)?
    var onFailure: ((String) -> Void)?
    private(set) var calls: [String] = []

    func start(at date: Date) { calls.append("start") }
    func pause() { calls.append("pause") }
    func resume() { calls.append("resume") }
    func end() { calls.append("end") }
}

@MainActor
final class FakeBuilder: RunWorkoutBuilder {
    var onHeartRate: ((Double) -> Void)?
    var onDistance: ((Double) -> Void)?
    var onQuantity: ((RunQuantity, Double) -> Void)?
    /// What `elapsedTime(at:)` answers; the tests move it.
    var elapsed: TimeInterval = 0
    private(set) var calls: [String] = []
    private(set) var events: [RunEvent] = []
    private(set) var metadata: [[String: Any]] = []
    private(set) var distanceSamples: [Double] = []
    private(set) var heartRateSamples: [Double] = []
    private(set) var routePoints = 0
    /// Failures to throw, counted down per call.
    var finishWorkoutFailures = 0
    var finishRouteFailures = 0
    var addEventsFailures = 0
    var beginCollectionFails = false

    func elapsedTime(at date: Date) -> TimeInterval { elapsed }

    func beginCollection(at date: Date) async throws {
        calls.append("begin")
        if beginCollectionFails { throw FakeFailure() }
    }

    func endCollection(at date: Date) async throws { calls.append("endCollection") }

    func finishWorkout() async throws {
        calls.append("finishWorkout")
        if finishWorkoutFailures > 0 {
            finishWorkoutFailures -= 1
            throw FakeFailure()
        }
    }

    func addMetadata(_ metadata: [String: Any]) async throws { self.metadata.append(metadata) }

    func addEvents(_ events: [RunEvent]) async throws {
        if addEventsFailures > 0 {
            addEventsFailures -= 1
            throw FakeFailure()
        }
        self.events += events
    }

    func addDistanceSample(meters: Double, from start: Date, to end: Date) async throws { distanceSamples.append(meters) }
    func addHeartRateSample(_ bpm: Double, at date: Date) async throws { heartRateSamples.append(bpm) }
    func insertRoute(_ locations: [CLLocation]) async throws { routePoints += locations.count }

    func finishRoute() async throws {
        calls.append("finishRoute")
        if finishRouteFailures > 0 {
            finishRouteFailures -= 1
            throw FakeFailure()
        }
    }

    func discard() { calls.append("discard") }
}

@MainActor
final class FakeBackend: RunBackend {
    var healthAllowed = true
    var healthRequestFails = false
    var locationAllowed = true
    var suppliesSensorReadings = false
    var batteryLevel: Float = 0.9
    var cueSettings = CueSettings()
    let session = FakeRunSession()
    let builder = FakeBuilder()
    private(set) var cues: [RunCue] = []
    private(set) var cancelledCues = 0
    private(set) var sensorCalls: [String] = []
    private(set) var sendLocations: (([CLLocation]) -> Void)?
    private(set) var sendHeartRate: ((Double) -> Void)?
    var locationDescription: String { locationAllowed ? "allowed" : "denied" }
    var locationDiagnostics: String { "fake" }

    func requestHealthAuthorization() async throws -> Bool {
        if healthRequestFails { throw FakeFailure() }
        return healthAllowed
    }

    func requestLocationAuthorization() async -> Bool { locationAllowed }
    func makeWorkout() throws -> (session: any RunWorkoutSession, builder: any RunWorkoutBuilder) { (session, builder) }

    func startSensors(onLocations: @escaping ([CLLocation]) -> Void, onHeartRate: @escaping (Double) -> Void) {
        sensorCalls.append("start")
        sendLocations = onLocations
        sendHeartRate = onHeartRate
    }

    func pauseSensors() { sensorCalls.append("pause") }
    func resumeSensors() { sensorCalls.append("resume") }
    func stopSensors() { sensorCalls.append("stop") }
    /// The spoken step announcements, kept apart so `cues` stays the haptic cues.
    private(set) var announcements: [String] = []
    /// How many countdown tones played.
    private(set) var ticks = 0
    func play(_ cue: RunCue) {
        switch cue {
        case .stepAnnouncement(let text): announcements.append(text)
        case .countdownTick: ticks += 1
        default: cues.append(cue)
        }
    }
    func cancelPendingCues() { cancelledCues += 1 }
    func battery(elapsed: TimeInterval) -> BatteryDisplay { BatteryDisplay(level: batteryLevel, isCharging: false) }
}

/// Lets the main actor run what the recorder started in a `Task` (the callbacks of a session).
/// Yields generously and for a short real time, so a longer chain of awaits can't make a test
/// depend on an exact count.
@MainActor
func settle() async {
    for _ in 0..<200 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(5))
}
