import Foundation

/// One piece of what the earbuds play: a tone signal or some words.
public enum CuePart: Sendable, Hashable {
    case tones([ToneNote])
    case speech(String)
}

/// What the queue needs from the audio system, so its logic can be tested without one
/// (`CueAudioPlayer` on the watch; a fake in tests).
@MainActor
public protocol CuePlaybackDriver: AnyObject {
    /// Takes the audio session, so podcasts pause and music is ducked. `false` when it can't.
    func activate() async -> Bool
    /// Lets the session go, so podcasts resume and music comes back up.
    func deactivate() async
    /// Starts a part and calls `finished` once when it has played to its end. A part that
    /// ``stop()`` cuts short never calls it.
    func play(_ part: CuePart, finished: @escaping @MainActor () -> Void)
    /// Stops what is playing, without calling `finished`.
    func stop()
}

/// Plays the sounds of the cues one after another (WATCH-107): a cue's tones and then its words,
/// and the next cue after them, so a step's tone and its announcement never talk over each other.
///
/// - The session is **held for a moment after the last part** (``linger``), not let go at once, so a
///   run of short tones (the countdown) doesn't make music duck and un-duck every second and
///   doesn't wait for the session each time.
/// - A cue marked `dropIfBusy` (a countdown tick) is skipped while something plays or the session
///   is being taken, since a late tick is worse than none.
/// - A backlog of more than ``capacity`` parts (a stalled session) drops further cues.
/// - ``cancel()`` forgets everything and lets the session go, also when it was cancelled in the
///   middle of taking it.
@MainActor
public final class CuePlaybackQueue {
    private enum Phase {
        /// No session held.
        case idle
        /// Waiting for the driver to take the session.
        case activating
        /// Session held and nothing playing: the next part starts, or the session is let go after the linger.
        case held
        case playing
    }

    /// The most parts waiting at once.
    public static let capacity = 6

    private let driver: any CuePlaybackDriver
    private let linger: Duration
    private var queue: [CuePart] = []
    private var phase = Phase.idle
    /// Counts the cancels, so what a cancelled run still reports back is ignored.
    private var generation = 0
    private var release: Task<Void, Never>?
    private var deactivation: Task<Void, Never>?

    /// - Parameters:
    ///   - driver: The audio system.
    ///   - linger: How long the session is held after the last part.
    public init(driver: any CuePlaybackDriver, linger: Duration = .milliseconds(1500)) {
        self.driver = driver
        self.linger = linger
    }

    /// Plays `sound` after what is already queued: its tones, then its words.
    ///
    /// - Parameters:
    ///   - sound: What to play.
    ///   - dropIfBusy: Skip it when something is playing or about to.
    public func play(_ sound: CueSound, dropIfBusy: Bool = false) {
        var parts: [CuePart] = []
        if !sound.tones.isEmpty { parts.append(.tones(sound.tones)) }
        if let words = sound.words { parts.append(.speech(words)) }
        guard !parts.isEmpty else { return }
        if dropIfBusy, phase == .activating || phase == .playing || !queue.isEmpty { return }
        guard queue.count + parts.count <= Self.capacity else { return }
        queue += parts
        release?.cancel()
        switch phase {
        case .idle: activate()
        case .held: playNext()
        case .activating, .playing: break
        }
    }

    /// Stops what plays, forgets what waits and lets the session go.
    public func cancel() {
        generation += 1
        queue = []
        release?.cancel()
        driver.stop()
        if phase != .idle { letGo() }
    }

    private func activate() {
        phase = .activating
        let generation = generation
        Task {
            // A session still being let go must be finished with before it is taken again.
            await deactivation?.value
            let activated = await driver.activate()
            guard generation == self.generation else {
                // Cancelled while activating. If nothing took over, nobody wants the session now.
                if activated, phase == .idle { letGo() }
                return
            }
            guard activated else {
                queue = []
                phase = .idle
                return
            }
            phase = .held
            playNext()
        }
    }

    private func playNext() {
        guard !queue.isEmpty else {
            phase = .held
            holdThenLetGo()
            return
        }
        phase = .playing
        let generation = generation
        driver.play(queue.removeFirst()) { [weak self] in
            guard let self, generation == self.generation else { return }
            self.playNext()
        }
    }

    private func holdThenLetGo() {
        release?.cancel()
        release = Task {
            try? await Task.sleep(for: linger)
            guard !Task.isCancelled, phase == .held, queue.isEmpty else { return }
            letGo()
        }
    }

    private func letGo() {
        phase = .idle
        let previous = deactivation
        deactivation = Task {
            await previous?.value
            await driver.deactivate()
        }
    }
}
