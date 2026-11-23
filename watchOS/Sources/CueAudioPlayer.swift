import AVFoundation
import TrainingWatchKit

/// The ears' side of the cues (WATCH-107): speech or tones through earbuds, or the watch speaker when the athlete
/// allows it (`CueSettings.sound`).
///
/// While a cue plays the audio session interrupts spoken audio (a podcast pauses) and ducks music;
/// it is let go when the cue is done, so they carry on at once. Which cue goes where is
/// `CueRouting` (tested); this only plays what it is told. Not tried on a real watch: whether
/// `currentRoute` shows earbuds before our session is active is to be checked (WATCH-122).
@MainActor
final class CueAudioPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var playing = 0
    /// Counts the plays and cancels, so the completion of a cue that was cancelled can't end the
    /// audio session of a newer one.
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

    func play(_ sound: CueSound) {
        guard begin() else { return }
        let generation = generation
        switch sound {
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

    /// Stops what is playing, for when the workout ends.
    func cancel() {
        synthesizer.stopSpeaking(at: .immediate)
        generation += 1
        node.stop()
        engine.stop()
        end(force: true)
    }

    // MARK: Session

    private func begin() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback, mode: .spokenAudio,
                options: [.interruptSpokenAudioAndMixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
            return false
        }
        playing += 1
        return true
    }

    private func end(force: Bool = false) {
        playing = force ? 0 : max(playing - 1, 0)
        guard playing == 0 else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.end() }
    }

    /// A cancel (`cancel()`) has already let the session go, so there is nothing to end here.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {}

    // MARK: Tones

    private func playTones(_ notes: [ToneNote], generation: Int) {
        let rate = 22_050.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { end(); return }
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
              let channel = buffer.floatChannelData?[0] else { end(); return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }

        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            end()
            return
        }
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.end()
            }
        }
        node.play()
    }
}
