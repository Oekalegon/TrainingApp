import Foundation

/// Whether the athlete hears speech or tones (WATCH-107), chosen in the iPhone app (``CueSettings``).
public enum AudioCueStyle: String, Sendable, CaseIterable, Hashable, Codable {
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

/// How the athlete wants to be told (WATCH-107): which channels and, for sound, speech or tones.
/// Chosen in the iPhone app and sent to the watch with the zones and the plan (``WatchContext``); the
/// watch keeps the last ones it got in its `UserDefaults`.
public struct CueSettings: Sendable, Hashable, Codable {
    /// When the wrist taps.
    public enum Haptics: String, Sendable, CaseIterable, Hashable, Codable {
        /// Zone alerts only without earbuds; step start, workout done and battery always.
        case automatic
        /// Every cue taps, with or without earbuds.
        case always
        case never
    }

    /// When the watch makes a sound.
    public enum Sound: String, Sendable, CaseIterable, Hashable, Codable {
        /// Only through earbuds.
        case automatic
        /// Also from the watch's speaker when no earbuds are connected.
        case always
        case never
    }

    public var haptics: Haptics
    public var sound: Sound
    public var style: AudioCueStyle

    public init(haptics: Haptics = .automatic, sound: Sound = .automatic, style: AudioCueStyle = .speech) {
        self.haptics = haptics
        self.sound = sound
        self.style = style
    }

    public static let hapticsKey = "cueHaptics"
    public static let soundKey = "cueSound"

    /// Keeps the settings for the next launch.
    public func save(in defaults: UserDefaults = .standard) {
        defaults.set(haptics.rawValue, forKey: Self.hapticsKey)
        defaults.set(sound.rawValue, forKey: Self.soundKey)
        defaults.set(style.rawValue, forKey: AudioCueStyle.defaultsKey)
    }

    /// The stored settings; the defaults for what was never chosen.
    public static func stored(in defaults: UserDefaults = .standard) -> CueSettings {
        CueSettings(
            haptics: defaults.string(forKey: hapticsKey).flatMap(Haptics.init(rawValue:)) ?? .automatic,
            sound: defaults.string(forKey: soundKey).flatMap(Sound.init(rawValue:)) ?? .automatic,
            style: AudioCueStyle.stored(in: defaults))
    }
}

/// Which channel a cue uses (`docs/design/watch-app.md`, "One signal per meaning" and "Audio"). By
/// default, with headphones connected the zone alerts are sound only and without them haptic only,
/// and the watch's own speaker is not used. Step started, workout done and battery warnings keep the
/// haptic as well. ``CueSettings`` can switch either channel on or off.
///
/// The tones and words are starting values; their final shape is WATCH-117.
public enum CueRouting {
    /// - Parameters:
    ///   - cue: What happened.
    ///   - headphonesConnected: Read when the cue fires, so taking earbuds out mid-run changes the channel.
    ///   - settings: The athlete's choices.
    public static func route(_ cue: RunCue, headphonesConnected: Bool, settings: CueSettings = CueSettings()) -> CueRoute {
        let soundAllowed = switch settings.sound {
        case .automatic: headphonesConnected
        case .always: true
        case .never: false
        }
        let base = baseRoute(cue, soundAllowed: soundAllowed, style: settings.style)
        let haptic: Bool
        switch settings.haptics {
        case .never: haptic = false
        case .always: haptic = hapticCue(cue)
        case .automatic: haptic = base.haptic
        }
        return CueRoute(haptic: haptic, sound: base.sound)
    }

    /// Cues that have a haptic at all (the announcement is words only).
    private static func hapticCue(_ cue: RunCue) -> Bool {
        if case .stepAnnouncement = cue { return false }
        return true
    }

    /// The automatic channels: the haptic where there is no sound to carry a zone alert, and for the
    /// rare cues that keep both.
    private static func baseRoute(_ cue: RunCue, soundAllowed: Bool, style: AudioCueStyle) -> CueRoute {
        guard soundAllowed else { return CueRoute(haptic: hapticCue(cue), sound: nil) }
        let haptic: Bool
        switch cue {
        case .zoneAlert(.stepStarted), .goalReached, .lapMarked, .batteryWarning: haptic = true
        case .zoneAlert, .stepAnnouncement: haptic = false
        }
        return CueRoute(haptic: haptic, sound: sound(for: cue, style: style))
    }

    /// What a cue sounds like: the words or the tones. One table, so the two can't drift apart and
    /// WATCH-117 can tune it without touching the channel rules. `nil` for a cue with no sound:
    /// a lap, the step-start alert in speech (the announcement says it) and the announcement in
    /// tones (the step-start tone stands for it).
    public static func sound(for cue: RunCue, style: AudioCueStyle) -> CueSound? {
        func pick(_ tones: [ToneNote], _ words: String) -> CueSound { style == .tones ? .tones(tones) : .speech(words) }
        switch cue {
        case .zoneAlert(let alert):
            switch alert {
            case .stepStarted: return style == .tones ? .tones(stepTones) : nil
            case .tooLow: return pick(tooLowTones, "Speed up")
            case .tooHigh: return pick(tooHighTones, "Slow down")
            case .farBelow: return pick(tooLowTones + tooLowTones, "Speed up now")
            case .farAbove: return pick(tooHighTones + tooHighTones, "Slow down now")
            case .backInZone: return pick(backTones, "In zone")
            }
        case .stepAnnouncement(let text): return style == .speech ? .speech(text) : nil
        case .goalReached: return pick(doneTones, "Workout done")
        case .lapMarked: return nil
        case .batteryWarning(let level):
            switch level {
            case .tight: return pick(batteryTones, "Battery low")
            case .critical: return pick(batteryTones, "Battery critical")
            case .runsOut: return pick(batteryTones, "Battery won't last")
            }
        }
    }

    private static let stepTones = [ToneNote(660, 0.12), ToneNote(660, 0.12)]
    private static let tooLowTones = [ToneNote(440, 0.15), ToneNote(660, 0.15)]
    private static let tooHighTones = [ToneNote(660, 0.15), ToneNote(440, 0.15)]
    private static let backTones = [ToneNote(880, 0.2)]
    private static let doneTones = [ToneNote(523, 0.15), ToneNote(659, 0.15), ToneNote(784, 0.3)]
    private static let batteryTones = [ToneNote(330, 0.3), ToneNote(330, 0.3)]
}
