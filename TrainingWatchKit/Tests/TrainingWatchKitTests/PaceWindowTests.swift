import Foundation
import Testing
@testable import TrainingWatchKit

@Suite("Current and average pace")
struct PaceWindowTests {
    private let metric = Locale(identifier: "nl_NL")
    private let us = Locale(identifier: "en_US")

    /// A run at a steady 3 m/s (5:33 per km), one reading a second.
    private func steady(seconds: Int, speed: Double = 3) -> PaceWindow {
        var window = PaceWindow()
        for second in 0...seconds { window.add(meters: Double(second) * speed, at: TimeInterval(second)) }
        return window
    }

    @Test("a steady speed gives its pace once there are a few seconds to measure")
    func steadyPace() throws {
        let pace = try #require(steady(seconds: 30).secondsPerMeter(at: 30))
        #expect(abs(pace - 1.0 / 3) < 0.0001)
    }

    @Test("no pace in the first seconds")
    func tooEarly() {
        #expect(steady(seconds: 3).secondsPerMeter(at: 3) == nil)
        #expect(PaceWindow().secondsPerMeter(at: 10) == nil)
    }

    @Test("only the last 20 seconds count: a faster stretch shows after the speed-up")
    func followsASpeedUp() throws {
        var window = PaceWindow()
        for second in 0...60 { window.add(meters: Double(second) * 2, at: TimeInterval(second)) }
        for second in 61...100 { window.add(meters: 120 + Double(second - 60) * 4, at: TimeInterval(second)) }
        let pace = try #require(window.secondsPerMeter(at: 100))
        #expect(abs(pace - 0.25) < 0.0001)
    }

    @Test("standing still is no pace")
    func standingStill() {
        var window = steady(seconds: 30)
        for second in 31...60 { window.add(meters: 90, at: TimeInterval(second)) }
        #expect(window.secondsPerMeter(at: 60) == nil)
    }

    @Test("a gap with no new distance shows as a slowing pace, not as the old one")
    func gapSlowsThePace() throws {
        let window = steady(seconds: 30)
        // Ten seconds later with no new distance: 10 s of the window were standing.
        let pace = try #require(window.secondsPerMeter(at: 40))
        #expect(pace > 1.0 / 3)
    }

    @Test("a new run starts the window again")
    func newRun() {
        var window = steady(seconds: 30)
        window.add(meters: 0, at: 0)
        #expect(window.secondsPerMeter(at: 1) == nil)
    }

    @Test("pace text is minutes and seconds per kilometre or mile")
    func text() {
        #expect(PaceText.text(secondsPerMeter: 0.332, locale: metric) == "5:32")
        #expect(PaceText.text(secondsPerMeter: 0.332, locale: us) == "8:54")
        #expect(PaceText.text(secondsPerMeter: nil, locale: metric) == "--")
        #expect(PaceText.text(secondsPerMeter: 4, locale: metric) == "--")
        #expect(PaceText.unit(metric) == "/km")
        #expect(PaceText.unit(us) == "/mi")
    }

    @Test("the average is the last reading's, so it holds still between readings and none in the first 50 m")
    func average() {
        var window = PaceWindow()
        window.add(meters: 20, at: 10)
        #expect(window.averageSecondsPerMeter == nil)
        window.add(meters: 2000, at: 600)
        #expect(window.averageSecondsPerMeter == 0.3)
    }

    @Test("distance in jumps a second apart doesn't make the current pace swing")
    func jumpsDoNotSwing() throws {
        // 3 m/s in jumps every 2 s.
        var window = PaceWindow()
        for second in stride(from: 0, through: 40, by: 2) { window.add(meters: Double(second) * 3, at: TimeInterval(second)) }
        let even = try #require(window.secondsPerMeter(at: 40))
        let odd = try #require(window.secondsPerMeter(at: 41))
        #expect(abs(even - odd) < 0.0001)
    }
}
