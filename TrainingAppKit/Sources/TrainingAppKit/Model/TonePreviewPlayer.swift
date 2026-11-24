import AVFoundation
import Observation
import TrainingWatchKit

/// Plays a tone on the phone so the athlete can hear what the watch will play (WATCH-117). The
/// tones are made by ``ToneNote/samples(_:)``, the same as on the watch, but come out of the phone's
/// speaker or earbuds, so the pitch is the same and the loudness is not.
@MainActor
@Observable
public final class TonePreviewPlayer {
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let node = AVAudioPlayerNode()

    public init() { engine.attach(node) }

    /// Plays `notes`, replacing what is playing.
    public func play(_ notes: [ToneNote]) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: ToneNote.sampleRate, channels: 1) else { return }
        let samples = ToneNote.samples(notes)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        node.stop()
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            return
        }
        node.scheduleBuffer(buffer, completionHandler: nil)
        node.play()
    }
}
