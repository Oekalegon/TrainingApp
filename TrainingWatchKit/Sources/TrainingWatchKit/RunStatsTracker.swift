import Foundation

/// Running statistics of a run for the run screens' catalogue (WATCH-135): the heart rate's average and
/// highest, the altitude, the climb so far and the grade of the last stretch. Pure, so it is tested without a
/// watch; `RunRecorder` feeds it the heart-rate readings and the GPS fixes.
public struct RunStatsTracker: Sendable {
    /// The climb is counted only once the altitude has moved this far (metres) from the last counted point,
    /// so GPS noise doesn't add up to a climb.
    public static let climbThreshold = 3.0
    /// The grade is taken over at least this many metres (and at most twice as many).
    public static let gradeWindowMeters = 50.0
    /// The most points kept for the grade: standing still adds fixes without adding distance.
    static let maximumPoints = 200
    /// A fix whose altitude is worse than this many metres is not used.
    public static let usableVerticalAccuracy = 20.0

    private var heartRateSum = 0.0
    private var heartRateCount = 0
    /// The highest heart rate so far.
    public private(set) var maxHeartRate: Double?
    /// The latest altitude in metres, or `nil` before a fix with a usable altitude. From the GPS, which is less exact
    /// than the watch's barometric altimeter (a later change), so the climb and the grade are rough.
    public private(set) var altitude: Double?
    /// The metres climbed so far.
    public private(set) var elevationGain = 0.0
    private var reference: Double?
    /// Recent (distance, altitude) points for the grade, at most ``maximumPoints``.
    private var recent: [(meters: Double, altitude: Double)] = []
    /// The whole run's altitude against distance for the elevation profile (WATCH-149), thinned as the run grows:
    /// at most ``maximumProfilePoints``, so a long run costs no more to keep or draw than a short one.
    public private(set) var profile: [ElevationPoint] = []
    /// The distance (metres) a point must be past the last profile point to be kept; doubles each time the profile is thinned.
    private var profileSpacing = 5.0
    static let maximumProfilePoints = 120
    /// The last stretch of the run for the "last 10 km" elevation graph (WATCH-149), at a finer spacing than ``profile``
    /// has on a long run: a point every ``recentSpacing`` metres, the ones further back than ``recentWindowMeters`` dropped.
    public private(set) var recentProfile: [ElevationPoint] = []
    public static let recentWindowMeters = 10_000.0
    public static let recentSpacing = 25.0

    public init() {}

    /// The mean of the heart-rate readings so far, or `nil` with none. A plain mean of the readings, not weighted
    /// by the time between them (they arrive about once a second on a watch, but a replay gives one per fix).
    public var averageHeartRate: Double? {
        heartRateCount == 0 ? nil : heartRateSum / Double(heartRateCount)
    }

    /// The slope over the last stretch in percent (positive uphill), or `nil` before enough distance.
    public var grade: Double? {
        guard let last = recent.last, let first = recent.first, last.meters - first.meters >= Self.gradeWindowMeters else { return nil }
        return (last.altitude - first.altitude) / (last.meters - first.meters) * 100
    }

    /// A heart-rate reading in beats per minute.
    public mutating func add(heartRate bpm: Double) {
        heartRateSum += bpm
        heartRateCount += 1
        maxHeartRate = max(maxHeartRate ?? bpm, bpm)
    }

    /// A GPS fix: its altitude in metres and the run's distance so far in metres.
    public mutating func add(altitude: Double, atDistance meters: Double) {
        self.altitude = altitude
        if let reference {
            if altitude - reference >= Self.climbThreshold {
                elevationGain += altitude - reference
                self.reference = altitude
            } else if reference - altitude >= Self.climbThreshold {
                self.reference = altitude
            }
        } else {
            reference = altitude
        }
        addToProfile(altitude: altitude, atDistance: meters)
        addToRecentProfile(altitude: altitude, atDistance: meters)
        // A fix at the same distance (standing still) replaces the last point instead of piling up.
        if let last = recent.last, last.meters == meters, recent.count > 1 {
            recent[recent.count - 1] = (meters, altitude)
        } else {
            recent.append((meters, altitude))
        }
        if recent.count > Self.maximumPoints { recent.removeFirst(recent.count - Self.maximumPoints) }
        // Keep one point at least a window back, so the grade always has a full stretch.
        while recent.count > 2, meters - recent[1].meters >= Self.gradeWindowMeters { recent.removeFirst() }
    }

    /// Keeps a point every ``recentSpacing`` metres and forgets those more than ``recentWindowMeters`` behind the run.
    /// At most 401 points however long the run is.
    private mutating func addToRecentProfile(altitude: Double, atDistance meters: Double) {
        if let last = recentProfile.last, meters - last.meters < Self.recentSpacing { return }
        recentProfile.append(ElevationPoint(meters: meters, altitude: altitude))
        let behind = meters - Self.recentWindowMeters
        if let first = recentProfile.first, first.meters < behind {
            recentProfile.removeAll { $0.meters < behind }
        }
    }

    /// Keeps a point once the run is ``profileSpacing`` metres past the last one; at the limit every other point goes
    /// and the spacing doubles, so the profile always spans the whole run. A fix less than the spacing past the last
    /// point (standing still) adds nothing.
    private mutating func addToProfile(altitude: Double, atDistance meters: Double) {
        guard let last = profile.last else {
            profile = [ElevationPoint(meters: meters, altitude: altitude)]
            return
        }
        if meters - last.meters >= profileSpacing {
            profile.append(ElevationPoint(meters: meters, altitude: altitude))
            if profile.count > Self.maximumProfilePoints {
                // Keep the first and the last point, thin the ones between.
                let lastPoint = profile[profile.count - 1]
                profile = profile.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
                if profile.last != lastPoint { profile.append(lastPoint) }
                profileSpacing *= 2
            }
        }
    }
}

/// One point of the elevation profile: the run's distance in metres and the altitude in metres there.
public struct ElevationPoint: Sendable, Hashable {
    public var meters: Double
    public var altitude: Double

    public init(meters: Double, altitude: Double) {
        self.meters = meters
        self.altitude = altitude
    }
}
