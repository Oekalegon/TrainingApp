import Foundation
import Testing
import TrainingCore

@testable import TrainingWatchKit

@Suite("Cue routing and announcements (WATCH-107)")
struct CueRoutingTests {
    private let zoneAlerts: [ZoneAlert] = [.tooLow, .tooHigh, .farBelow, .farAbove, .backInZone]
    private let bothOn = SignalSound(tone: true, speech: true)
    private func settings(_ sound: SignalSound, haptics: CueSettings.Haptics = .automatic, channel: CueSettings.Sound = .automatic) -> CueSettings {
        CueSettings(haptics: haptics, sound: channel, signals: Dictionary(uniqueKeysWithValues: SignalKind.allCases.map { ($0, sound) }))
    }

    @Test("without headphones every cue is a haptic only and the speaker is never used")
    func noHeadphones() {
        for cue in [RunCue.zoneAlert(.tooLow), .zoneAlert(.stepStarted), .goalReached, .lapMarked, .batteryWarning(.critical)] {
            let route = CueRouting.route(cue, headphonesConnected: false, settings: settings(bothOn))
            #expect(route.haptic && route.sound == nil)
        }
        #expect(CueRouting.route(.stepAnnouncement("x"), headphonesConnected: false, settings: settings(bothOn))
            == CueRoute(haptic: false, sound: nil))
    }

    @Test("with headphones the zone alerts are sound only, and step start, done and battery keep the haptic")
    func channels() {
        for alert in zoneAlerts {
            let route = CueRouting.route(.zoneAlert(alert), headphonesConnected: true, settings: settings(bothOn))
            #expect(!route.haptic && route.sound != nil)
        }
        for cue in [RunCue.zoneAlert(.stepStarted), .goalReached, .batteryWarning(.tight)] {
            let route = CueRouting.route(cue, headphonesConnected: true, settings: settings(bothOn))
            #expect(route.haptic && route.sound != nil)
        }
    }

    @Test("each signal plays its tone, its words, or the tone and then the words")
    func toneAndSpeech() {
        let cue = RunCue.zoneAlert(.tooHigh)
        let both = CueRouting.route(cue, headphonesConnected: true, settings: settings(bothOn)).sound
        #expect(both?.words == "Slow down" && both?.tones.isEmpty == false)
        let toneOnly = CueRouting.route(cue, headphonesConnected: true, settings: settings(SignalSound(tone: true, speech: false))).sound
        #expect(toneOnly?.words == nil && toneOnly?.tones.isEmpty == false)
        let speechOnly = CueRouting.route(cue, headphonesConnected: true, settings: settings(SignalSound(tone: false, speech: true))).sound
        #expect(speechOnly?.words == "Slow down" && speechOnly?.tones.isEmpty == true)
    }

    @Test("the choice is per signal: speech for step starts, tones only for out of and back in the zone")
    func perSignal() {
        var custom = CueSettings()
        custom[.stepStart] = SignalSound(tone: false, speech: true)
        custom[.belowZone] = SignalSound(tone: true, speech: false)
        custom[.backInZone] = SignalSound(tone: true, speech: false)
        #expect(CueRouting.route(.stepAnnouncement("Recovery"), headphonesConnected: true, settings: custom).sound
            == CueSound(words: "Recovery"))
        #expect(CueRouting.route(.zoneAlert(.stepStarted), headphonesConnected: true, settings: custom).sound == nil)
        #expect(CueRouting.route(.zoneAlert(.tooLow), headphonesConnected: true, settings: custom).sound?.words == nil)
        #expect(CueRouting.route(.zoneAlert(.backInZone), headphonesConnected: true, settings: custom).sound?.words == nil)
    }

    @Test("the countdown tick is the step-start tone only, dropped if busy, and never a haptic or speech")
    func countdownTick() {
        let both = CueRouting.route(.countdownTick, headphonesConnected: true, settings: settings(bothOn, haptics: .always))
        #expect(both.sound?.words == nil && both.sound?.tones.isEmpty == false && both.sound?.dropIfBusy == true && !both.haptic)
        var speechOnly = CueSettings()
        speechOnly[.stepStart] = SignalSound(tone: false, speech: true)
        #expect(CueRouting.route(.countdownTick, headphonesConnected: true, settings: speechOnly).sound == nil)
        #expect(!CueRouting.route(.countdownTick, headphonesConnected: false, settings: CueSettings()).haptic)
    }

    @Test("the step-start tone is longer than a countdown tick")
    func startToneLonger() {
        func length(_ cue: RunCue) -> TimeInterval {
            CueRouting.route(cue, headphonesConnected: true, settings: CueSettings()).sound?.tones.map(\.duration).reduce(0, +) ?? 0
        }
        #expect(length(.zoneAlert(.stepStarted)) > 3 * length(.countdownTick))
    }

    @Test("a step announcement is silent when speech is off for step starts")
    func announcementNeedsSpeech() {
        var custom = CueSettings()
        custom[.stepStart] = SignalSound(tone: true, speech: false)
        #expect(CueRouting.route(.stepAnnouncement("x"), headphonesConnected: true, settings: custom).sound == nil)
    }

    @Test("a zone alert with neither tone nor speech is a haptic, so it is not lost")
    func nothingChosen() {
        let none = settings(SignalSound(tone: false, speech: false))
        let route = CueRouting.route(.zoneAlert(.tooLow), headphonesConnected: true, settings: none)
        #expect(route.sound == nil && route.haptic)
    }

    @Test("sound can be switched on without earbuds, or off with them")
    func soundSetting() {
        let route = CueRouting.route(.zoneAlert(.tooLow), headphonesConnected: false, settings: settings(bothOn, channel: .always))
        #expect(route.sound != nil && !route.haptic)
        let off = CueRouting.route(.zoneAlert(.tooLow), headphonesConnected: true, settings: settings(bothOn, channel: .never))
        #expect(off.sound == nil && off.haptic)
    }

    @Test("haptics can be always or never")
    func hapticSetting() {
        let both = CueRouting.route(.zoneAlert(.tooLow), headphonesConnected: true, settings: settings(bothOn, haptics: .always))
        #expect(both.haptic && both.sound != nil)
        #expect(!CueRouting.route(.stepAnnouncement("x"), headphonesConnected: true, settings: settings(bothOn, haptics: .always)).haptic)
        let never = settings(bothOn, haptics: .never)
        #expect(!CueRouting.route(.goalReached, headphonesConnected: false, settings: never).haptic)
        #expect(CueRouting.route(.goalReached, headphonesConnected: true, settings: never).sound != nil)
    }

    @Test("the zone alerts sound different from one another")
    func tonesDiffer() {
        let sounds = zoneAlerts.map {
            CueRouting.route(.zoneAlert($0), headphonesConnected: true, settings: settings(SignalSound(tone: true, speech: false))).sound
        }
        #expect(Set(sounds.compactMap { $0 }).count == zoneAlerts.count)
    }

    @Test("every cue but a lap belongs to a signal, and far alerts to their direction's")
    func kinds() {
        #expect(SignalKind(.lapMarked) == nil && SignalKind(.countdownTick) == .stepStart)
        #expect(SignalKind(.zoneAlert(.farBelow)) == .belowZone && SignalKind(.zoneAlert(.farAbove)) == .aboveZone)
        #expect(SignalKind(.stepAnnouncement("x")) == .stepStart && SignalKind(.zoneAlert(.stepStarted)) == .stepStart)
    }

    @Test("a step is announced in words, and a work step ahead as the next step")
    func announcement() {
        let metric = Locale(identifier: "en_NL")
        func planned(_ step: WorkoutStep, repetition: Int = 1, of repetitions: Int = 1) -> PlannedStep {
            PlannedStep(index: 0, step: step, blockIndex: 0, repetition: repetition, repetitions: repetitions)
        }
        let interval = planned(WorkoutStep(kind: .work, goal: .time(240), target: .heartRateZone(4)), repetition: 3, of: 6)
        #expect(StepAnnouncement.text(for: interval, locale: metric) == "Interval 3 of 6, 4 minutes, zone 4")
        #expect(StepAnnouncement.text(for: interval, locale: metric, ahead: true) == "Next: work for 4 minutes, zone 4")
        #expect(StepAnnouncement.text(
            for: planned(WorkoutStep(kind: .work, goal: .distance(800))), locale: metric, ahead: true)
            == "Next: work for 800 metres")
        #expect(StepAnnouncement.text(for: planned(WorkoutStep(kind: .warmup, goal: .time(90))), locale: metric)
            == "Warm-up, 1 minute 30 seconds")
        #expect(StepAnnouncement.text(for: planned(WorkoutStep(kind: .cooldown, goal: .distance(1500))), locale: metric)
            == "Cool-down, 1.5 kilometres")
        #expect(StepAnnouncement.text(for: planned(WorkoutStep(kind: .recovery, goal: .distance(400))), locale: metric)
            == "Recovery, 400 metres")
        #expect(StepAnnouncement.text(for: planned(WorkoutStep(kind: .work, goal: .open)), locale: metric) == "Run, open")
    }

    @Test("only a work step after a timed step is announced ahead, once the lead time is reached")
    func ahead() {
        func step(_ kind: StepKind) -> PlannedStep {
            PlannedStep(index: 1, step: WorkoutStep(kind: kind, goal: .time(60)), blockIndex: 0, repetition: 1, repetitions: 1)
        }
        func progress(_ remaining: TimeInterval?) -> StepProgress {
            StepProgress(remainingTime: remaining, remainingDistance: nil, fraction: nil)
        }
        let on = CueSettings(aheadSeconds: 10)
        #expect(StepAnnouncement.announcesAhead(next: step(.work), progress: progress(10), settings: on))
        #expect(!StepAnnouncement.announcesAhead(next: step(.work), progress: progress(11), settings: on))
        #expect(!StepAnnouncement.announcesAhead(next: step(.recovery), progress: progress(5), settings: on))
        #expect(!StepAnnouncement.announcesAhead(next: step(.work), progress: progress(nil), settings: on))
        #expect(!StepAnnouncement.announcesAhead(next: nil, progress: progress(5), settings: on))
        #expect(!StepAnnouncement.announcesAhead(
            next: step(.work), progress: progress(5), settings: CueSettings(announceWorkAhead: false)))
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
