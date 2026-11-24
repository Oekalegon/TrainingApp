import AVFoundation
import TrainingWatchKit

/// The ears' side of the cues (WATCH-107): tones and speech through earbuds, or the
/// watch speaker when the athlete allows it (`CueSettings.sound`).
///
/// While a cue plays the audio session interrupts spoken audio (a podcast pauses) and ducks music;
/// it is let go when the cue is done, so they carry on at once. Which cue goes where is
/// `CueRouting` (tested); this only plays what it is told. Not tried on a real watch: whether
/// `currentRoute` shows earbuds before our session is active is to be checked (WATCH-122).
@MainActor
final class CueAudioPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private enum Part {
        case speech(String)
        case tones([ToneNote])
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    /// What is still to play, in order: a cue's tones, then its words, then the next cue's.
    private var queue: [Part] = []
    /// Whether a part is playing, and the audio session is ours.
    private var busy = false
    /// Whether the session is active, so parts can play; false while it is being activated.
    private var sessionActive = false
    private var activating = false
    /// The session being let go, which a new activation waits for, so the two can't cross.
    private var deactivation: Task<Void, Never>?
    /// Counts the cancels, so the completion of a part that was cancelled can't carry on with
    /// the queue of a newer cue.
    private var generation = 0

    override init() {
        super.init()
        synthesizer.delegate = self
        engine.attach(node)
    }

    /// Whether earbuds or headphones are the audio output now.
    var headphonesConnected: Bool {
        let wanted: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { wanted.contains($0.portType) }
    }

    /// Plays `sound` after whatever is playing, so a step's tone and its announcement don't talk
    /// over each other. A long backlog (cues piling up in a stalled session) is dropped.
    func play(_ sound: CueSound) {
        var parts: [Part] = []
        if !sound.tones.isEmpty { parts.append(.tones(sound.tones)) }
        if let words = sound.words { parts.append(.speech(words)) }
        // A countdown tick that would have to wait for speech to finish would come late: drop it.
        if sound.dropIfBusy, busy { return }
        guard queue.count < 6 else { return }
        queue += parts
        if !busy { startNext() }
    }

    /// Stops what is playing and forgets what is waiting, for when the workout ends.
    func cancel() {
        generation += 1
        queue = []
        synthesizer.stopSpeaking(at: .immediate)
        node.stop()
        engine.stop()
        finish()
    }

    // MARK: Queue

    /// Carries on with the queue: the next part, or, when it is empty, lets the session go. The
    /// first part waits for the session to be activated, which is asynchronous so the main thread
    /// never blocks on it.
    private func startNext() {
        guard !queue.isEmpty else { finish(); return }
        guard sessionActive else {
            guard !activating else { return }
            activating = true
            busy = true
            let generation = generation
            Task {
                let activated = await activateSession()
                activating = false
                guard generation == self.generation else {
                    // Cancelled while activating: nobody wants the session now.
                    if activated, !busy { await deactivateSession() }
                    return
                }
                guard activated else {
                    queue = []
                    busy = false
                    return
                }
                sessionActive = true
                startNext()
            }
            return
        }
        switch queue.removeFirst() {
        case .speech(let words):
            let utterance = AVSpeechUtterance(string: words)
            // The words are English until they are localised (WATCH-123), so the voice is too: a
            // Dutch voice reading English is unintelligible.
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            synthesizer.speak(utterance)
        case .tones(let notes):
            playTones(notes, generation: generation)
        }
    }

    /// The queue is empty: let the session go, so podcasts resume and music comes back up.
    private func finish() {
        guard busy else { return }
        busy = false
        sessionActive = false
        deactivation = Task { await deactivateSession() }
    }

    // MARK: Session

    private func activateSession() async -> Bool {
        await deactivation?.value
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback, mode: .spokenAudio,
                options: [.interruptSpokenAudioAndMixWithOthers, .duckOthers])
            _ = try await session.activate()
            return true
        } catch {
            return false
        }
    }

    /// Off the main thread: `setActive(false)` blocks, and the asynchronous `deactivate` needs
    /// watchOS 27.
    private func deactivateSession() async {
        await Task.detached {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }.value
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.startNext() }
    }

    /// A cancel (`cancel()`) has already let the session go, so there is nothing to carry on with.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {}

    // MARK: Tones

    private func playTones(_ notes: [ToneNote], generation: Int) {
        let rate = 22_050.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { startNext(); return }
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
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { startNext(); return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }

        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            startNext()
            return
        }
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.startNext()
            }
        }
        node.play()
    }
}
