import Foundation

/// Whether the athlete hears speech or tones in earbuds (WATCH-107). A setting on the watch for now.
public enum AudioCueStyle: String, Sendable, CaseIterable, Hashable {
    case speech
    case tones

    /// The `UserDefaults` key the watch keeps the setting under.
    public static let defaultsKey = "audioCueStyle"

    /// The stored setting; speech when none was chosen.
    public static func stored(in defaults: UserDefaults = .standard) -> AudioCueStyle {
        defaults.string(forKey: defaultsKey).flatMap(AudioCueStyle.init(rawValue:)) ?? .speech
    }
}

/// One note of a tone signal.
public struct ToneNote: Sendable, Hashable {
    /// Pitch in hertz.
    public let frequency: Double
    /// Length in seconds.
    public let duration: TimeInterval

    public init(_ frequency: Double, _ duration: TimeInterval) {
        self.frequency = frequency
        self.duration = duration
    }
}

/// What the earbuds play for a cue.
public enum CueSound: Sendable, Hashable {
    case speech(String)
    case tones([ToneNote])
}

/// How one cue reaches the athlete: the wrist, the earbuds, or both.
public struct CueRoute: Sendable, Hashable {
    public let haptic: Bool
    public let sound: CueSound?
}

/// Which channel a cue uses (`docs/design/watch-app.md`, "One signal per meaning" and "Audio"):
/// with headphones connected the zone alerts are sound only, without them haptic only, and the watch's
/// own speaker is never used. Step started, workout done and battery warnings keep the haptic as well.
///
/// The tones and words are starting values; their final shape is WATCH-117.
public enum CueRouting {
    /// - Parameters:
    ///   - cue: What happened.
    ///   - headphonesConnected: Read when the cue fires, so taking earbuds out mid-run changes the channel.
    ///   - style: Speech or tones.
    public static func route(_ cue: RunCue, headphonesConnected: Bool, style: AudioCueStyle) -> CueRoute {
        guard headphonesConnected else {
            // No speaker, ever: only the haptic, and nothing for the announcement text.
            if case .stepAnnouncement = cue { return CueRoute(haptic: false, sound: nil) }
            return CueRoute(haptic: true, sound: nil)
        }
        switch cue {
        case .zoneAlert(let alert):
            switch alert {
            case .stepStarted: return CueRoute(haptic: true, sound: sound(.tones(stepTones), "", style))
            case .tooLow: return CueRoute(haptic: false, sound: sound(.tones(tooLowTones), "Speed up", style))
            case .tooHigh: return CueRoute(haptic: false, sound: sound(.tones(tooHighTones), "Slow down", style))
            case .farBelow:
                return CueRoute(haptic: false, sound: sound(.tones(tooLowTones + tooLowTones), "Speed up now", style))
            case .farAbove:
                return CueRoute(haptic: false, sound: sound(.tones(tooHighTones + tooHighTones), "Slow down now", style))
            case .backInZone: return CueRoute(haptic: false, sound: sound(.tones(backTones), "In zone", style))
            }
        case .stepAnnouncement(let text):
            // The announcement is the speech version of the step-start signal; tones already have theirs.
            return CueRoute(haptic: false, sound: style == .speech ? .speech(text) : nil)
        case .goalReached:
            return CueRoute(haptic: true, sound: sound(.tones(doneTones), "Workout done", style))
        case .lapMarked:
            return CueRoute(haptic: true, sound: nil)
        case .batteryWarning(let level):
            let words = switch level {
            case .tight: "Battery low"
            case .critical: "Battery critical"
            case .runsOut: "Battery won't last"
            }
            return CueRoute(haptic: true, sound: sound(.tones(batteryTones), words, style))
        }
    }

    /// The sound for `style`: the given tones, or the words. An empty word means speech has nothing
    /// to say here (the step announcement does it).
    private static func sound(_ tones: CueSound, _ words: String, _ style: AudioCueStyle) -> CueSound? {
        switch style {
        case .tones: tones
        case .speech: words.isEmpty ? nil : .speech(words)
        }
    }

    private static let stepTones = [ToneNote(660, 0.12), ToneNote(660, 0.12)]
    private static let tooLowTones = [ToneNote(440, 0.15), ToneNote(660, 0.15)]
    private static let tooHighTones = [ToneNote(660, 0.15), ToneNote(440, 0.15)]
    private static let backTones = [ToneNote(880, 0.2)]
    private static let doneTones = [ToneNote(523, 0.15), ToneNote(659, 0.15), ToneNote(784, 0.3)]
    private static let batteryTones = [ToneNote(330, 0.3), ToneNote(330, 0.3)]
}
