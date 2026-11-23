import TrainingWatchKit
import WatchKit

/// The wrist's side of the zone alerts (WATCH-106): one haptic per kind of alert. Starting values
/// that already differ clearly, to be tuned on a real watch with the tones (WATCH-117); no sound
/// yet, so no headphones channel either (WATCH-107).
@MainActor
enum ZoneAlertHaptics {
    /// Plays the haptic for `alert`. The far alerts are the ordinary direction twice, so they stay
    /// distinguishable as above or below and feel more urgent.
    static func play(_ alert: ZoneAlert) {
        // A far alert's second tap must not land after a newer alert or the end of the workout.
        secondTap?.cancel()
        let device = WKInterfaceDevice.current()
        switch alert {
        case .stepStarted: device.play(.notification)
        case .tooLow: device.play(.directionUp)
        case .tooHigh: device.play(.directionDown)
        case .backInZone: device.play(.success)
        case .farBelow: twice(.directionUp, on: device)
        case .farAbove: twice(.directionDown, on: device)
        }
    }

    /// Drops a far alert's second tap that hasn't played yet, for when the workout ends.
    static func cancelPending() { secondTap?.cancel() }

    private static var secondTap: Task<Void, Never>?

    private static func twice(_ type: WKHapticType, on device: WKInterfaceDevice) {
        device.play(type)
        secondTap = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            device.play(type)
        }
    }
}
