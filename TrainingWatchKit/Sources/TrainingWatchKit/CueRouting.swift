import Foundation

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

/// What the earbuds play for a cue: tones, words, or the tones and then the words.
public struct CueSound: Sendable, Hashable {
    /// The tone signal; empty for none.
    public var tones: [ToneNote]
    /// The words to say after the tones; `nil` for none.
    public var words: String?

    public init(tones: [ToneNote] = [], words: String? = nil) {
        self.tones = tones
        self.words = words
    }
}

/// How one cue reaches the athlete: the wrist, the earbuds, or both.
public struct CueRoute: Sendable, Hashable {
    public let haptic: Bool
    public let sound: CueSound?
}

/// A kind of signal the athlete can set the sound of (WATCH-107): each has its own choice of tone
/// and speech.
public enum SignalKind: String, Sendable, CaseIterable, Hashable, Codable, Identifiable {
    /// A step begins (and its announcement).
    case stepStart
    /// Under the target zone: speed up (far or not).
    case belowZone
    /// Over the target zone: slow down (far or not).
    case aboveZone
    /// Back in the target zone.
    case backInZone
    /// The workout's last step is over.
    case workoutDone
    /// A battery warning.
    case battery

    public var id: String { rawValue }

    /// The name in the iPhone app.
    public var title: String {
        switch self {
        case .stepStart: "Step Starts"
        case .belowZone: "Below Zone"
        case .aboveZone: "Above Zone"
        case .backInZone: "Back in Zone"
        case .workoutDone: "Workout Done"
        case .battery: "Battery Warning"
        }
    }

    /// The signal a cue belongs to; `nil` for a lap, which is a haptic only.
    public init?(_ cue: RunCue) {
        switch cue {
        case .zoneAlert(let alert):
            switch alert {
            case .stepStarted: self = .stepStart
            case .tooLow, .farBelow: self = .belowZone
            case .tooHigh, .farAbove: self = .aboveZone
            case .backInZone: self = .backInZone
            }
        case .stepAnnouncement: self = .stepStart
        case .goalReached: self = .workoutDone
        case .batteryWarning: self = .battery
        case .lapMarked: return nil
        }
    }
}

/// Whether a signal plays its tone, its words, both (the tone first) or neither.
public struct SignalSound: Sendable, Hashable, Codable {
    public var tone: Bool
    public var speech: Bool

    public init(tone: Bool = true, speech: Bool = false) {
        self.tone = tone
        self.speech = speech
    }
}

/// How the athlete wants to be told (WATCH-107): which channels, and for each kind of signal whether
/// it has a tone, speech or both. Chosen in the iPhone app and sent to the watch with the zones and
/// the plan (``WatchContext``); the watch keeps the last ones it got in its `UserDefaults`.
public struct CueSettings: Sendable, Hashable, Codable {
    /// When the wrist taps.
    public enum Haptics: String, Sendable, CaseIterable, Hashable, Codable {
        /// A zone alert only when it has no sound; step start, workout done and battery always.
        case automatic
        /// Every cue taps, with or without sound.
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
    /// Whether a work step is announced shortly before it starts, so the athlete can get ready for
    /// it; other steps are announced as they start. A step that can't be foreseen (after an open
    /// step, or one with a distance goal) is announced as it starts.
    public var announceWorkAhead: Bool
    /// How long before a work step starts it is announced, in seconds.
    public var aheadSeconds: Int

    /// Each kind's tone and speech, by raw value, so it encodes as a plain object.
    private var signals: [String: SignalSound]

    public init(
        haptics: Haptics = .automatic, sound: Sound = .automatic, announceWorkAhead: Bool = true,
        aheadSeconds: Int = 10, signals: [SignalKind: SignalSound] = [:]
    ) {
        self.haptics = haptics
        self.sound = sound
        self.announceWorkAhead = announceWorkAhead
        self.aheadSeconds = aheadSeconds
        self.signals = Dictionary(uniqueKeysWithValues: signals.map { ($0.key.rawValue, $0.value) })
    }

    /// What a kind plays when the athlete hasn't chosen: the step changes and the end are heard and
    /// spoken, and the zone alerts and warnings are tones, which are quicker to take in mid-effort.
    public static func defaultSound(of kind: SignalKind) -> SignalSound {
        switch kind {
        case .stepStart, .workoutDone, .battery: SignalSound(tone: true, speech: true)
        case .belowZone, .aboveZone, .backInZone: SignalSound(tone: true, speech: false)
        }
    }

    public subscript(kind: SignalKind) -> SignalSound {
        get { signals[kind.rawValue] ?? Self.defaultSound(of: kind) }
        set { signals[kind.rawValue] = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case haptics, sound, announceWorkAhead, aheadSeconds, signals
    }

    /// Each part is read on its own with its default, so settings from a phone with an older or newer
    /// app still give the watch what it can understand.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        haptics = (try? container.decodeIfPresent(Haptics.self, forKey: .haptics)) ?? .automatic
        sound = (try? container.decodeIfPresent(Sound.self, forKey: .sound)) ?? .automatic
        announceWorkAhead = (try? container.decodeIfPresent(Bool.self, forKey: .announceWorkAhead)) ?? true
        aheadSeconds = (try? container.decodeIfPresent(Int.self, forKey: .aheadSeconds)) ?? 10
        signals = (try? container.decodeIfPresent([String: SignalSound].self, forKey: .signals)) ?? [:]
    }

    private static let defaultsKey = "cueSettings.v2"

    /// Keeps the settings for the next launch.
    public func save(in defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }

    /// The stored settings; the defaults for what was never chosen.
    public static func stored(in defaults: UserDefaults = .standard) -> CueSettings {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(CueSettings.self, from: $0) }
            ?? CueSettings()
    }
}

/// Which channel a cue uses (`docs/design/watch-app.md`, "One signal per meaning" and "Audio"), by
/// the athlete's ``CueSettings``. By default, with headphones connected a zone alert is sound only
/// and without them haptic only, and the watch's own speaker is not used. Step started, workout
/// done and battery warnings keep the haptic as well. A zone alert whose signal has no tone and no
/// speech chosen is a haptic, so it isn't lost.
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
        let sound = soundAllowed ? sound(for: cue, settings: settings) : nil
        let automatic: Bool
        switch cue {
        case .lapMarked, .goalReached, .batteryWarning, .zoneAlert(.stepStarted): automatic = true
        case .stepAnnouncement: automatic = false
        case .zoneAlert: automatic = sound == nil
        }
        let haptic: Bool
        switch settings.haptics {
        case .never: haptic = false
        case .always: haptic = hapticCue(cue)
        case .automatic: haptic = automatic
        }
        return CueRoute(haptic: haptic, sound: sound)
    }

    /// Cues that have a haptic at all (the announcement is words only).
    private static func hapticCue(_ cue: RunCue) -> Bool {
        if case .stepAnnouncement = cue { return false }
        return true
    }

    /// What the cue sounds like with the athlete's choice for its signal: its tones if the tone is
    /// on, then its words if speech is on; `nil` when neither is, or for a cue with no sound (a lap).
    /// One table of tones and words, so the two can't drift apart and WATCH-117 can tune it without
    /// touching the channel rules.
    public static func sound(for cue: RunCue, settings: CueSettings) -> CueSound? {
        guard let kind = SignalKind(cue) else { return nil }
        let choice = settings[kind]
        let (tones, words) = material(for: cue)
        let sound = CueSound(tones: choice.tone ? tones : [], words: choice.speech ? words : nil)
        return sound.tones.isEmpty && sound.words == nil ? nil : sound
    }

    /// A cue's tones and its words. The step-start alert has only its tone and the announcement
    /// only its words (the text is the step's), so the two together are the step's signal.
    private static func material(for cue: RunCue) -> (tones: [ToneNote], words: String?) {
        switch cue {
        case .zoneAlert(let alert):
            switch alert {
            case .stepStarted: return (stepTones, nil)
            case .tooLow: return (tooLowTones, "Speed up")
            case .tooHigh: return (tooHighTones, "Slow down")
            case .farBelow: return (tooLowTones + tooLowTones, "Speed up now")
            case .farAbove: return (tooHighTones + tooHighTones, "Slow down now")
            case .backInZone: return (backTones, "In zone")
            }
        case .stepAnnouncement(let text): return ([], text)
        case .goalReached: return (doneTones, "Workout done")
        case .lapMarked: return ([], nil)
        case .batteryWarning(let level):
            switch level {
            case .tight: return (batteryTones, "Battery low")
            case .critical: return (batteryTones, "Battery critical")
            case .runsOut: return (batteryTones, "Battery won't last")
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
