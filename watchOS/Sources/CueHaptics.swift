import TrainingWatchKit
import WatchKit

/// The wrist's side of the cues (WATCH-106, WATCH-117): plays the ``HapticPlan`` that `CueRouting`
/// made from the athlete's choice for the cue's signal. Whether a haptic plays at all, or the
/// earbuds do instead, is decided by `CueRouting` (WATCH-107).
@MainActor
enum CueHaptics {
    /// Plays the pattern `taps` times, half a second apart, so a far alert or a worse battery warning
    /// is the same signal, more urgent.
    static func play(_ plan: HapticPlan) {
        // A later tap must not land after a newer cue or the end of the workout.
        laterTaps?.cancel()
        let device = WKInterfaceDevice.current()
        device.play(type(plan.pattern))
        guard plan.taps > 1 else { return }
        laterTaps = Task {
            for _ in 1..<plan.taps {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                device.play(type(plan.pattern))
            }
        }
    }

    /// Drops the taps that haven't played yet, for when the workout ends.
    static func cancelPending() { laterTaps?.cancel() }

    private static var laterTaps: Task<Void, Never>?

    private static func type(_ pattern: HapticPattern) -> WKHapticType {
        switch pattern {
        case .notification: .notification
        case .directionUp: .directionUp
        case .directionDown: .directionDown
        case .success: .success
        case .failure: .failure
        case .retry: .retry
        case .start: .start
        case .stop: .stop
        case .click: .click
        }
    }
}
