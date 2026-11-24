import Foundation

/// A haptic the athlete can give a kind of signal (WATCH-117). Each is one of the watch's own taps,
/// so the watch app maps the case to a `WKHapticType`; the pattern can only be judged on a real
/// watch, which is why the athlete can change it.
public enum HapticPattern: String, Sendable, CaseIterable, Hashable, Codable, Identifiable {
    case notification, directionUp, directionDown, success, failure, retry, start, stop, click

    public var id: String { rawValue }

    /// The name in the iPhone app.
    public var title: String {
        switch self {
        case .notification: "Notification"
        case .directionUp: "Rising"
        case .directionDown: "Falling"
        case .success: "Success"
        case .failure: "Failure"
        case .retry: "Retry"
        case .start: "Start"
        case .stop: "Stop"
        case .click: "Click"
        }
    }
}

/// A tone the athlete can give a kind of signal (WATCH-117). Starting values, tuned by ear.
public enum TonePattern: String, Sendable, CaseIterable, Hashable, Codable, Identifiable {
    case longBeep, risingPair, fallingPair, highBlip, fanfare, lowDouble, doubleBeep

    public var id: String { rawValue }

    /// The name in the iPhone app.
    public var title: String {
        switch self {
        case .longBeep: "Long Beep"
        case .risingPair: "Two Notes Up"
        case .fallingPair: "Two Notes Down"
        case .highBlip: "High Blip"
        case .fanfare: "Fanfare"
        case .lowDouble: "Low Double Beep"
        case .doubleBeep: "Double Beep"
        }
    }

    /// The notes played.
    public var notes: [ToneNote] {
        switch self {
        case .longBeep: [ToneNote(660, 0.6)]
        case .risingPair: [ToneNote(440, 0.15), ToneNote(660, 0.15)]
        case .fallingPair: [ToneNote(660, 0.15), ToneNote(440, 0.15)]
        case .highBlip: [ToneNote(880, 0.2)]
        case .fanfare: [ToneNote(523, 0.15), ToneNote(659, 0.15), ToneNote(784, 0.3)]
        case .lowDouble: [ToneNote(330, 0.3), ToneNote(330, 0.3)]
        case .doubleBeep: [ToneNote(1000, 0.12), ToneNote(1000, 0.12)]
        }
    }
}

/// The haptic of a cue: a pattern, tapped `taps` times (a far alert and a worse battery warning
/// tap more, so they stay the same signal but feel more urgent).
public struct HapticPlan: Sendable, Hashable {
    public let pattern: HapticPattern
    public let taps: Int

    public init(_ pattern: HapticPattern, taps: Int = 1) {
        self.pattern = pattern
        self.taps = taps
    }
}

extension SignalKind {
    /// What a kind feels like when the athlete hasn't chosen. The step, the two out-of-zone
    /// directions, back in the zone, the end and the battery each differ.
    public var defaultHaptic: HapticPattern {
        switch self {
        case .stepStart: .notification
        case .belowZone: .directionUp
        case .aboveZone: .directionDown
        case .backInZone: .start
        case .workoutDone: .success
        case .battery: .retry
        }
    }

    /// What a kind sounds like when the athlete hasn't chosen.
    public var defaultTone: TonePattern {
        switch self {
        case .stepStart: .longBeep
        case .belowZone: .risingPair
        case .aboveZone: .fallingPair
        case .backInZone: .highBlip
        case .workoutDone: .fanfare
        case .battery: .lowDouble
        }
    }
}

extension ToneNote {
    /// The sample rate the tones are made at.
    public static let sampleRate = 22_050.0

    /// The notes as mono samples, each with a short fade at both ends so it doesn't click, and a
    /// short silence after it. The watch plays them as a cue and the phone as a preview (WATCH-117),
    /// so the two sound the same.
    public static func samples(_ notes: [ToneNote]) -> [Float] {
        let rate = sampleRate
        var samples: [Float] = []
        for note in notes {
            let count = Int(note.duration * rate)
            let fade = max(Int(0.01 * rate), 1)
            for index in 0..<count {
                let edge = min(index, count - index, fade)
                let envelope = Float(edge) / Float(fade)
                samples.append(envelope * 0.5 * Float(sin(2 * .pi * note.frequency * Double(index) / rate)))
            }
            samples.append(contentsOf: [Float](repeating: 0, count: Int(0.05 * rate)))
        }
        return samples
    }
}
