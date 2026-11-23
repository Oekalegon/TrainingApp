import CoreLocation
import Foundation

/// A segment or lap marker written into the workout being recorded (WATCH-104). The watch app turns
/// it into an `HKWorkoutEvent`.
///
/// It carries `[String: Any]` metadata, so it isn't `Sendable`: it only travels between the
/// main-actor recorder and the main-actor backend.
public struct RunEvent {
    public enum Kind: Sendable, Hashable {
        case segment
        case lap
    }

    public let kind: Kind
    public let start: Date
    public let end: Date
    public let metadata: [String: Any]?

    public init(kind: Kind, start: Date, end: Date, metadata: [String: Any]?) {
        self.kind = kind
        self.start = start
        self.end = end
        self.metadata = metadata
    }
}

/// The state a recording session reports, reduced to what ``RunRecorder`` reacts to.
public enum RunSessionState: Sendable, Hashable {
    case running
    case paused
    /// The session has ended; the workout can be saved.
    case ended
    /// Any other state (not started, prepared, stopped), which needs no reaction.
    case other
}

/// A signal for the athlete: the backend picks the haptic and the sound (``CueRouting`` decides
/// which channels and what they play).
public enum RunCue: Sendable, Hashable {
    /// A zone alert (WATCH-106).
    case zoneAlert(ZoneAlert)
    /// The last step of a planned workout is over.
    case goalReached
    /// A lap was marked in a free run.
    case lapMarked
    /// The words for a step that began, said in earbuds in the speech setting (WATCH-107).
    case stepAnnouncement(String)
    /// A battery warning of this level (WATCH-110).
    case batteryWarning(BatteryWarning.Level)
}

/// The workout session (`HKWorkoutSession` on the watch). Callbacks arrive on the main actor.
@MainActor
public protocol RunWorkoutSession: AnyObject {
    /// Called when the session changes state, whoever caused it: the button, the system or the end.
    var onStateChange: ((RunSessionState) -> Void)? { get set }
    /// Called with a message when the session fails.
    var onFailure: ((String) -> Void)? { get set }

    func start(at date: Date)
    func pause()
    func resume()
    func end()
}

/// The workout builder with its route (`HKLiveWorkoutBuilder` and `HKWorkoutRouteBuilder` on the watch).
@MainActor
public protocol RunWorkoutBuilder: AnyObject {
    /// Called with the latest heart rate in beats per minute, when the builder collects one. A
    /// backend that supplies its own readings (the simulator) never calls it.
    var onHeartRate: ((Double) -> Void)? { get set }
    /// Called with the total distance in metres so far, when the builder has one. Never called by
    /// a backend that supplies its own readings.
    var onDistance: ((Double) -> Void)? { get set }

    /// Elapsed workout time at `date`, without paused time.
    func elapsedTime(at date: Date) -> TimeInterval
    func beginCollection(at date: Date) async throws
    func endCollection(at date: Date) async throws
    /// Saves the workout.
    func finishWorkout() async throws
    func addMetadata(_ metadata: [String: Any]) async throws
    func addEvents(_ events: [RunEvent]) async throws
    func addDistanceSample(meters: Double, from start: Date, to end: Date) async throws
    func addHeartRateSample(_ bpm: Double, at date: Date) async throws
    func insertRoute(_ locations: [CLLocation]) async throws
    /// Saves the route with the workout `finishWorkout()` saved.
    func finishRoute() async throws
    /// Throws the unsaved workout and its route away.
    func discard()
}

/// Everything ``RunRecorder`` needs from the outside world: HealthKit, GPS, the wrist and the
/// battery. The watch app has the real one; tests have a fake.
@MainActor
public protocol RunBackend: AnyObject {
    /// Asks for the Health permissions (a no-op once answered) and returns whether workouts can be
    /// saved; throws when the request itself fails.
    func requestHealthAuthorization() async throws -> Bool
    /// Asks for location access and returns whether it was granted.
    func requestLocationAuthorization() async -> Bool
    /// Makes a session and its builder for a new outdoor run.
    func makeWorkout() throws -> (session: any RunWorkoutSession, builder: any RunWorkoutBuilder)

    /// Whether the backend supplies the locations and heart rate itself and the builder collects
    /// none (the simulator), so the recorder derives the distance from the locations and adds the
    /// heart-rate samples to the workout.
    var suppliesSensorReadings: Bool { get }
    /// Starts the GPS (and, for a backend that supplies readings, the heart rate).
    func startSensors(
        onLocations: @escaping ([CLLocation]) -> Void, onHeartRate: @escaping (Double) -> Void)
    func pauseSensors()
    func resumeSensors()
    func stopSensors()

    /// The location permission and the location counters, for the simulator's debug line.
    var locationDescription: String { get }
    var locationDiagnostics: String { get }

    func play(_ cue: RunCue)
    /// Drops a cue that hasn't played yet (a far alert's second tap), for when the workout ends.
    func cancelPendingCues()
    /// The battery now, `elapsed` seconds into the run.
    func battery(elapsed: TimeInterval) -> BatteryDisplay
}
