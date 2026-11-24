import AVFoundation
import TrainingWatchKit

/// The audio system under the cues (WATCH-107): speech from `AVSpeechSynthesizer` and generated
/// tones, through earbuds, or the watch speaker when the athlete allows it (`CueSettings.sound`).
///
/// The order, the holding of the session and the cancelling are `CuePlaybackQueue`'s (tested); this
/// only does what the queue asks. While the session is active it interrupts spoken audio (a podcast
/// pauses) and ducks music. Not tried on a real watch: whether `currentRoute` shows earbuds before
/// our session is active is to be checked (WATCH-122).
@MainActor
final class CueAudioPlayer: NSObject, AVSpeechSynthesizerDelegate, CuePlaybackDriver {
    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    /// What to call when the part now playing ends; one call, then it is forgotten.
    private var finished: (@MainActor () -> Void)?
    /// Counts the parts started, so the end of a part that was stopped (a buffer's completion, a
    /// speech that finishes late) can't end the one that replaced it.
    private var token = 0
    private var utterance: AVSpeechUtterance?
    private lazy var queue = CuePlaybackQueue(driver: self)

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

    func play(_ sound: CueSound, dropIfBusy: Bool = false) { queue.play(sound, dropIfBusy: dropIfBusy) }

    /// Stops what is playing and forgets what is waiting, for when the workout ends.
    func cancel() { queue.cancel() }

    // MARK: CuePlaybackDriver

    func activate() async -> Bool {
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
    func deactivate() async {
        await Task.detached {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }.value
    }

    func play(_ part: CuePart, finished: @escaping @MainActor () -> Void) {
        self.finished = finished
        token += 1
        switch part {
        case .speech(let words):
            let utterance = AVSpeechUtterance(string: words)
            // The words are English until they are localised (WATCH-123), so the voice is too: a
            // Dutch voice reading English is unintelligible.
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            self.utterance = utterance
            synthesizer.speak(utterance)
        case .tones(let notes):
            playTones(notes)
        }
    }

    func stop() {
        finished = nil
        token += 1
        utterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        node.stop()
        engine.stop()
    }

    private func partEnded() {
        let call = finished
        finished = nil
        call?()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let ended = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard let current = self.utterance, ObjectIdentifier(current) == ended else { return }
            self.utterance = nil
            self.partEnded()
        }
    }

    // MARK: Tones

    private func playTones(_ notes: [ToneNote]) {
        let rate = 22_050.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { partEnded(); return }
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
              let channel = buffer.floatChannelData?[0] else { partEnded(); return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }

        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            partEnded()
            return
        }
        // A stopped node also calls this; the token has moved on by then, so it does nothing.
        let token = token
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.token == token else { return }
                self.partEnded()
            }
        }
        node.play()
    }
}
