import Foundation
import Testing
import TrainingCore

@testable import TrainingWatchKit

@Suite("Cue routing and announcements (WATCH-107)")
struct CueRoutingTests {
    private let zoneAlerts: [ZoneAlert] = [.tooLow, .tooHigh, .farBelow, .farAbove, .backInZone]

    @Test("without headphones every cue is a haptic only and the speaker is never used")
    func noHeadphones() {
        for style in AudioCueStyle.allCases {
            for cue in [RunCue.zoneAlert(.tooLow), .zoneAlert(.stepStarted), .goalReached, .lapMarked,
                        .batteryWarning(.critical)] {
                let route = CueRouting.route(cue, headphonesConnected: false, settings: CueSettings(style: style))
                #expect(route.haptic && route.sound == nil)
            }
            #expect(CueRouting.route(.stepAnnouncement("x"), headphonesConnected: false, settings: CueSettings(style: style))
                == CueRoute(haptic: false, sound: nil))
        }
    }

    @Test("with headphones the zone alerts are sound only")
    func zoneAlertsSoundOnly() {
        for alert in zoneAlerts {
            for style in AudioCueStyle.allCases {
                let route = CueRouting.route(.zoneAlert(alert), headphonesConnected: true, settings: CueSettings(style: style))
                #expect(!route.haptic)
                #expect(route.sound != nil)
            }
        }
    }

    @Test("step start, workout done and battery keep the haptic with headphones")
    func hapticAndSound() {
        for cue in [RunCue.zoneAlert(.stepStarted), .goalReached, .batteryWarning(.tight)] {
            let route = CueRouting.route(cue, headphonesConnected: true, settings: CueSettings(style: .tones))
            #expect(route.haptic && route.sound != nil)
        }
    }

    @Test("sound can be switched on without earbuds, or off with them")
    func soundSetting() {
        let speaker = CueSettings(sound: .always)
        // Without earbuds but with sound on, a zone alert is sound only, as it is with earbuds.
        let route = CueRouting.route(.zoneAlert(.tooLow), headphonesConnected: false, settings: speaker)
        #expect(route.sound != nil && !route.haptic)
        let off = CueRouting.route(.zoneAlert(.tooLow), headphonesConnected: true, settings: CueSettings(sound: .never))
        // With no sound at all, the haptic carries the alert.
        #expect(off.sound == nil && off.haptic)
    }

    @Test("haptics can be always or never")
    func hapticSetting() {
        let always = CueSettings(haptics: .always)
        let both = CueRouting.route(.zoneAlert(.tooLow), headphonesConnected: true, settings: always)
        #expect(both.haptic && both.sound != nil)
        #expect(!CueRouting.route(.stepAnnouncement("x"), headphonesConnected: true, settings: always).haptic)
        let never = CueSettings(haptics: .never)
        #expect(!CueRouting.route(.goalReached, headphonesConnected: false, settings: never).haptic)
        #expect(CueRouting.route(.goalReached, headphonesConnected: true, settings: never).sound != nil)
    }

    @Test("speech plays the tones and then the words; tones play the tones alone; the announcement is only spoken")
    func style() {
        let speech = CueRouting.route(.zoneAlert(.tooHigh), headphonesConnected: true, settings: CueSettings(style: .speech)).sound
        if case .tonesThenSpeech(let notes, let words)? = speech {
            #expect(!notes.isEmpty && words == "Slow down")
        } else {
            Issue.record("expected tones then speech")
        }
        if case .tones(let notes)? = CueRouting.route(.zoneAlert(.tooHigh), headphonesConnected: true, settings: CueSettings(style: .tones)).sound {
            #expect(!notes.isEmpty)
        } else {
            Issue.record("expected tones")
        }
        #expect(CueRouting.route(.stepAnnouncement("Warm-up"), headphonesConnected: true, settings: CueSettings(style: .speech)).sound
            == .speech("Warm-up"))
        #expect(CueRouting.route(.stepAnnouncement("Warm-up"), headphonesConnected: true, settings: CueSettings(style: .tones)).sound == nil)
        // The step-start alert is its tone in both; in speech the announcement follows with the words.
        for style in AudioCueStyle.allCases {
            if case .tones? = CueRouting.route(.zoneAlert(.stepStarted), headphonesConnected: true, settings: CueSettings(style: style)).sound {} else {
                Issue.record("expected the step tone")
            }
        }
    }

    @Test("the zone alerts sound different from one another in tones")
    func tonesDiffer() {
        let sounds = zoneAlerts.map { CueRouting.route(.zoneAlert($0), headphonesConnected: true, settings: CueSettings(style: .tones)).sound }
        #expect(Set(sounds.compactMap { $0 }).count == zoneAlerts.count)
    }

    @Test("a step is announced in words")
    func announcement() {
        let metric = Locale(identifier: "en_NL")
        func planned(_ step: WorkoutStep, repetition: Int = 1, of repetitions: Int = 1) -> PlannedStep {
            PlannedStep(index: 0, step: step, blockIndex: 0, repetition: repetition, repetitions: repetitions)
        }
        #expect(StepAnnouncement.text(
            for: planned(WorkoutStep(kind: .work, goal: .time(240), target: .heartRateZone(4)), repetition: 3, of: 6),
            locale: metric) == "Interval 3 of 6, 4 minutes, zone 4")
        #expect(StepAnnouncement.text(for: planned(WorkoutStep(kind: .warmup, goal: .time(90))), locale: metric)
            == "Warm-up, 1 minute 30 seconds")
        #expect(StepAnnouncement.text(for: planned(WorkoutStep(kind: .cooldown, goal: .distance(1500))), locale: metric)
            == "Cool-down, 1.5 kilometres")
        #expect(StepAnnouncement.text(for: planned(WorkoutStep(kind: .recovery, goal: .distance(400))), locale: metric)
            == "Recovery, 400 metres")
        #expect(StepAnnouncement.text(for: planned(WorkoutStep(kind: .work, goal: .open)), locale: metric)
            == "Run, open")
    }
}

@Suite("Cue settings travel to the watch (WATCH-107)")
struct CueSettingsTransferTests {
    @Test("the settings survive the application context")
    func contextRoundTrip() throws {
        let settings = CueSettings(haptics: .always, sound: .always, style: .tones)
        let context = WatchContext(cues: settings)
        let decoded = try #require(WatchContext(applicationContext: try context.applicationContext()))
        #expect(decoded.cues == settings)
    }

    @Test("a context without settings leaves them out, and unreadable ones are dropped")
    func missing() throws {
        let plain = try #require(WatchContext(applicationContext: try WatchContext().applicationContext()))
        #expect(plain.cues == nil)
        let json = #"{"cues":{"haptics":"nonsense"}}"#.data(using: .utf8)!
        #expect(WatchContext(data: json)?.cues == nil)
    }

    @Test("stored settings are read back, and speech with automatic channels is the default")
    func storage() throws {
        let defaults = try #require(UserDefaults(suiteName: "CueSettingsTests-\(UUID().uuidString)"))
        #expect(CueSettings.stored(in: defaults) == CueSettings())
        let settings = CueSettings(haptics: .never, sound: .never, style: .tones)
        settings.save(in: defaults)
        #expect(CueSettings.stored(in: defaults) == settings)
    }
}

@Suite("Announcements for other targets (WATCH-107)")
struct StepAnnouncementTargetTests {
    private func text(_ step: WorkoutStep) -> String {
        StepAnnouncement.text(
            for: PlannedStep(index: 0, step: step, blockIndex: 0, repetition: 1, repetitions: 1),
            locale: Locale(identifier: "en_NL"))
    }

    @Test("a zone range and a bpm range are spoken, and a step with no heart-rate target says only its goal")
    func targets() {
        #expect(text(WorkoutStep(kind: .work, goal: .time(60), target: .heartRateZoneRange(3.5...4))) == "Run, 1 minute, zone 3.5 to 4")
        #expect(text(WorkoutStep(kind: .work, goal: .time(60), target: .heartRateRange(150, 160)))
            == "Run, 1 minute, 150 to 160 beats per minute")
        #expect(text(WorkoutStep(kind: .work, goal: .time(60))) == "Run, 1 minute")
    }

    @Test("miles for a US locale")
    func miles() {
        let step = PlannedStep(
            index: 0, step: WorkoutStep(kind: .work, goal: .distance(1609.344)), blockIndex: 0, repetition: 1, repetitions: 1)
        #expect(StepAnnouncement.text(for: step, locale: Locale(identifier: "en_US")) == "Run, 1 mile")
    }
}
