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
    /// Whether to skip the sound when something is playing, instead of waiting its turn: a
    /// countdown tick that comes late is worse than none.
    public let dropIfBusy: Bool

    public init(haptic: Bool, sound: CueSound?, dropIfBusy: Bool = false) {
        self.haptic = haptic
        self.sound = sound
        self.dropIfBusy = dropIfBusy
    }
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
        case .stepAnnouncement, .countdownTick: self = .stepStart
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
    /// How long before a work step starts it is announced, in seconds (``aheadRange``).
    public var aheadSeconds: Int {
        didSet { aheadSeconds = Self.aheadRange.clamp(aheadSeconds) }
    }

    /// The lead times the athlete can choose, which also bounds what the watch accepts from the phone.
    public static let aheadRange = 5...30

    /// Each kind's tone and speech, by raw value, so it encodes as a plain object.
    private var signals: [String: SignalSound]
    /// Each kind's haptic and tone when the athlete changed it (WATCH-117).
    private var haptics_: [String: HapticPattern] = [:]
    private var tones_: [String: TonePattern] = [:]

    public init(
        haptics: Haptics = .automatic, sound: Sound = .automatic, announceWorkAhead: Bool = true,
        aheadSeconds: Int = 10, signals: [SignalKind: SignalSound] = [:]
    ) {
        self.haptics = haptics
        self.sound = sound
        self.announceWorkAhead = announceWorkAhead
        self.aheadSeconds = Self.aheadRange.clamp(aheadSeconds)
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

    /// The haptic a kind taps; the athlete's choice or the kind's default (WATCH-117).
    public func haptic(of kind: SignalKind) -> HapticPattern { haptics_[kind.rawValue] ?? kind.defaultHaptic }

    /// The tone a kind plays; the athlete's choice or the kind's default (WATCH-117).
    public func tone(of kind: SignalKind) -> TonePattern { tones_[kind.rawValue] ?? kind.defaultTone }

    public mutating func setHaptic(_ pattern: HapticPattern, of kind: SignalKind) { haptics_[kind.rawValue] = pattern }
    public mutating func setTone(_ pattern: TonePattern, of kind: SignalKind) { tones_[kind.rawValue] = pattern }

    private enum CodingKeys: String, CodingKey {
        case haptics, sound, announceWorkAhead, aheadSeconds, signals, hapticPatterns, tonePatterns
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(haptics, forKey: .haptics)
        try container.encode(sound, forKey: .sound)
        try container.encode(announceWorkAhead, forKey: .announceWorkAhead)
        try container.encode(aheadSeconds, forKey: .aheadSeconds)
        try container.encode(signals, forKey: .signals)
        try container.encode(haptics_.mapValues(\.rawValue), forKey: .hapticPatterns)
        try container.encode(tones_.mapValues(\.rawValue), forKey: .tonePatterns)
    }

    /// Each part is read on its own with its default, so settings from a phone with an older or newer
    /// app still give the watch what it can understand.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        haptics = (try? container.decodeIfPresent(Haptics.self, forKey: .haptics)) ?? .automatic
        sound = (try? container.decodeIfPresent(Sound.self, forKey: .sound)) ?? .automatic
        announceWorkAhead = (try? container.decodeIfPresent(Bool.self, forKey: .announceWorkAhead)) ?? true
        aheadSeconds = Self.aheadRange.clamp((try? container.decodeIfPresent(Int.self, forKey: .aheadSeconds)) ?? 10)
        signals = (try? container.decodeIfPresent([String: SignalSound].self, forKey: .signals)) ?? [:]
        // As raw strings, so a pattern a newer app added falls back to the default, not to a failure.
        let hapticNames = (try? container.decodeIfPresent([String: String].self, forKey: .hapticPatterns)) ?? [:]
        let toneNames = (try? container.decodeIfPresent([String: String].self, forKey: .tonePatterns)) ?? [:]
        haptics_ = hapticNames.compactMapValues(HapticPattern.init(rawValue:))
        tones_ = toneNames.compactMapValues(TonePattern.init(rawValue:))
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
/// The tones, words and haptics are starting values the athlete can change per signal (WATCH-117).
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
        case .stepAnnouncement, .countdownTick: automatic = false
        case .zoneAlert: automatic = sound == nil
        }
        let haptic: Bool
        switch settings.haptics {
        case .never: haptic = false
        case .always: haptic = hapticCue(cue)
        case .automatic: haptic = automatic
        }
        if case .countdownTick = cue { return CueRoute(haptic: haptic, sound: sound, dropIfBusy: true) }
        return CueRoute(haptic: haptic, sound: sound)
    }

    /// Cues that have a haptic at all (the announcement is words only, the countdown tones only).
    private static func hapticCue(_ cue: RunCue) -> Bool {
        switch cue {
        case .stepAnnouncement, .countdownTick: return false
        default: return true
        }
    }

    /// What the cue sounds like with the athlete's choice for its signal: its tones if the tone is
    /// on, then its words if speech is on; `nil` when neither is, or for a cue with no sound (a lap).
    /// One table of tones and words, so the two can't drift apart.
    public static func sound(for cue: RunCue, settings: CueSettings) -> CueSound? {
        guard let kind = SignalKind(cue) else { return nil }
        let choice = settings[kind]
        let (tones, words) = material(for: cue, settings: settings)
        let sound = CueSound(tones: choice.tone ? tones : [], words: choice.speech ? words : nil)
        return sound.tones.isEmpty && sound.words == nil ? nil : sound
    }

    /// A cue's tones and its words. The step-start alert has only its tone and the announcement
    /// only its words (the text is the step's), so the two together are the step's signal.
    private static func material(for cue: RunCue, settings: CueSettings) -> (tones: [ToneNote], words: String?) {
        func tones(_ kind: SignalKind, times: Int = 1) -> [ToneNote] {
            Array(repeating: settings.tone(of: kind).notes, count: times).flatMap { $0 }
        }
        switch cue {
        case .zoneAlert(let alert):
            switch alert {
            case .stepStarted: return (tones(.stepStart), nil)
            case .tooLow: return (tones(.belowZone), "Speed up")
            case .tooHigh: return (tones(.aboveZone), "Slow down")
            case .farBelow: return (tones(.belowZone, times: 2), "Speed up now")
            case .farAbove: return (tones(.aboveZone, times: 2), "Slow down now")
            case .backInZone: return (tones(.backInZone), "In zone")
            }
        case .stepAnnouncement(let text): return ([], text)
        case .countdownTick: return (tickTones, nil)
        case .goalReached: return (tones(.workoutDone), "Workout done")
        case .lapMarked: return ([], nil)
        case .batteryWarning(let level):
            switch level {
            case .tight: return (tones(.battery), "Battery low")
            case .critical: return (tones(.battery, times: 2), "Battery critical")
            case .runsOut: return (tones(.battery, times: 3), "Battery won't last")
            }
        }
    }

    /// The haptic of a cue, with the athlete's pattern for its signal; `nil` for the announcement and
    /// the countdown, which have none. A lap is always a click.
    public static func hapticPlan(for cue: RunCue, settings: CueSettings) -> HapticPlan? {
        switch cue {
        case .stepAnnouncement, .countdownTick: return nil
        case .lapMarked: return HapticPlan(.click)
        default: break
        }
        guard let kind = SignalKind(cue) else { return nil }
        let pattern = settings.haptic(of: kind)
        switch cue {
        case .zoneAlert(.farBelow), .zoneAlert(.farAbove), .batteryWarning(.critical): return HapticPlan(pattern, taps: 2)
        case .batteryWarning(.runsOut): return HapticPlan(pattern, taps: 3)
        default: return HapticPlan(pattern)
        }
    }

    /// A short tone for each second of the countdown, and a longer, lower one as the step starts.
    private static let tickTones = [ToneNote(1000, 0.08)]
}

private extension ClosedRange where Bound == Int {
    func clamp(_ value: Int) -> Int { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
