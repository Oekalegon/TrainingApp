import Testing

@testable import TrainingWatchKit

@MainActor
private final class FakeDriver: CuePlaybackDriver {
    var activationResult = true
    /// When set, activation waits until `finishActivation()`.
    var holdActivation = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var activations = 0
    private(set) var deactivations = 0
    private(set) var played: [CuePart] = []
    private(set) var stops = 0
    private var finish: (@MainActor () -> Void)?

    func activate() async -> Bool {
        activations += 1
        if holdActivation { await withCheckedContinuation { waiting.append($0) } }
        return activationResult
    }

    func deactivate() async { deactivations += 1 }

    func play(_ part: CuePart, finished: @escaping @MainActor () -> Void) {
        played.append(part)
        finish = finished
    }

    func stop() {
        stops += 1
        finish = nil
    }

    /// Lets the oldest waiting activation finish.
    func finishActivation() { if !waiting.isEmpty { waiting.removeFirst().resume() } }
    func finishPart() { let call = finish; finish = nil; call?() }
}

private let beep = CueSound(tones: [ToneNote(440, 0.1)])
private let beepAndWords = CueSound(tones: [ToneNote(440, 0.1)], words: "Slow down")

@MainActor
@Suite("CuePlaybackQueue (WATCH-107)")
struct CuePlaybackQueueTests {
    private func make(linger: Duration = .milliseconds(30)) -> (CuePlaybackQueue, FakeDriver) {
        let driver = FakeDriver()
        return (CuePlaybackQueue(driver: driver, linger: linger), driver)
    }

    @Test("a cue plays its tones and then its words, one at a time")
    func order() async {
        let (queue, driver) = make()
        queue.play(beepAndWords)
        await settle()
        #expect(driver.played == [.tones(beep.tones)])
        driver.finishPart()
        await settle()
        #expect(driver.played == [.tones(beep.tones), .speech("Slow down")])
    }

    @Test("the next cue waits for the one before")
    func cuesQueue() async {
        let (queue, driver) = make()
        queue.play(beep)
        queue.play(CueSound(words: "Next"))
        await settle()
        #expect(driver.played.count == 1)
        driver.finishPart()
        await settle()
        #expect(driver.played.last == .speech("Next"))
    }

    @Test("the session is held between short cues, and let go once after the linger")
    func linger() async {
        let (queue, driver) = make(linger: .milliseconds(80))
        queue.play(beep)
        await settle()
        driver.finishPart()
        try? await Task.sleep(for: .milliseconds(20))
        queue.play(beep)
        await settle()
        driver.finishPart()
        #expect(driver.activations == 1 && driver.deactivations == 0)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(driver.activations == 1 && driver.deactivations == 1)
        queue.play(beep)
        await settle()
        #expect(driver.activations == 2)
    }

    @Test("a tick is dropped while something plays or is being started, and plays while the session is merely held")
    func dropIfBusy() async {
        let (queue, driver) = make(linger: .milliseconds(200))
        queue.play(beep)
        queue.play(beep, dropIfBusy: true)
        await settle()
        #expect(driver.played.count == 1)
        driver.finishPart()
        await settle()
        queue.play(beep, dropIfBusy: true)
        await settle()
        #expect(driver.played.count == 2)
    }

    @Test("a backlog over the capacity drops the cues that don't fit")
    func capacity() async {
        let (queue, driver) = make()
        for _ in 0..<10 { queue.play(beep) }
        await settle()
        for _ in 0..<10 { driver.finishPart(); await settle() }
        #expect(driver.played.count == CuePlaybackQueue.capacity)
    }

    @Test("a failed activation forgets the cue and the next one tries again")
    func activationFails() async {
        let (queue, driver) = make()
        driver.activationResult = false
        queue.play(beep)
        await settle()
        #expect(driver.played.isEmpty)
        driver.activationResult = true
        queue.play(beep)
        await settle()
        #expect(driver.played.count == 1 && driver.activations == 2)
    }

    @Test("a cancel stops what plays, forgets what waits and lets the session go")
    func cancel() async {
        let (queue, driver) = make()
        queue.play(beepAndWords)
        await settle()
        queue.cancel()
        await settle()
        #expect(driver.stops == 1 && driver.deactivations == 1)
        driver.finishPart()  // a part that was cut short reports nothing
        await settle()
        #expect(driver.played.count == 1)
    }

    @Test("a cue played while a cancelled activation is still pending is not stranded")
    func playAfterCancelDuringActivation() async {
        let (queue, driver) = make()
        driver.holdActivation = true
        queue.play(beep)
        await settle()
        queue.cancel()
        queue.play(CueSound(words: "Again"))
        await settle()
        // The first activation finishes and is ignored; the second one carries the new cue.
        driver.finishActivation()
        await settle()
        #expect(driver.played.isEmpty)
        driver.finishActivation()
        await settle()
        #expect(driver.played == [.speech("Again")])
    }

    @Test("a cancel during activation with nothing after it leaves the session let go")
    func cancelDuringActivation() async {
        let (queue, driver) = make()
        driver.holdActivation = true
        queue.play(beep)
        await settle()
        queue.cancel()
        driver.finishActivation()
        await settle()
        #expect(driver.played.isEmpty && driver.deactivations >= 1)
    }
}
