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
                let route = CueRouting.route(cue, headphonesConnected: false, style: style)
                #expect(route.haptic && route.sound == nil)
            }
            #expect(CueRouting.route(.stepAnnouncement("x"), headphonesConnected: false, style: style)
                == CueRoute(haptic: false, sound: nil))
        }
    }

    @Test("with headphones the zone alerts are sound only")
    func zoneAlertsSoundOnly() {
        for alert in zoneAlerts {
            for style in AudioCueStyle.allCases {
                let route = CueRouting.route(.zoneAlert(alert), headphonesConnected: true, style: style)
                #expect(!route.haptic)
                #expect(route.sound != nil)
            }
        }
    }

    @Test("step start, workout done and battery keep the haptic with headphones")
    func hapticAndSound() {
        for cue in [RunCue.zoneAlert(.stepStarted), .goalReached, .batteryWarning(.tight)] {
            let route = CueRouting.route(cue, headphonesConnected: true, style: .tones)
            #expect(route.haptic && route.sound != nil)
        }
    }

    @Test("the style picks words or tones, and the announcement is only spoken")
    func style() {
        #expect(CueRouting.route(.zoneAlert(.tooHigh), headphonesConnected: true, style: .speech).sound
            == .speech("Slow down"))
        if case .tones(let notes)? = CueRouting.route(.zoneAlert(.tooHigh), headphonesConnected: true, style: .tones).sound {
            #expect(!notes.isEmpty)
        } else {
            Issue.record("expected tones")
        }
        #expect(CueRouting.route(.stepAnnouncement("Warm-up"), headphonesConnected: true, style: .speech).sound
            == .speech("Warm-up"))
        #expect(CueRouting.route(.stepAnnouncement("Warm-up"), headphonesConnected: true, style: .tones).sound == nil)
        // In speech the announcement says it; the step-start alert itself stays silent.
        #expect(CueRouting.route(.zoneAlert(.stepStarted), headphonesConnected: true, style: .speech).sound == nil)
    }

    @Test("the zone alerts sound different from one another in tones")
    func tonesDiffer() {
        let sounds = zoneAlerts.map { CueRouting.route(.zoneAlert($0), headphonesConnected: true, style: .tones).sound }
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
