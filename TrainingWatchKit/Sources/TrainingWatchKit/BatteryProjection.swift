import Foundation

/// What the battery will be at the end of the planned workout, worded for the dial (WATCH-119):
/// "~44% AT END", or "EMPTY IN 0:42" when it will run out first, with how that rates. Pure, so the
/// wording and the thresholds are tested; the dial only shows it.
public struct BatteryProjection: Sendable, Hashable {
    /// The line for the screen, such as "~44% AT END" or "EMPTY IN 0:42".
    public let text: String
    /// The same for VoiceOver, such as "about 44 percent at the end".
    public let spoken: String
    /// How the end charge rates.
    public let verdict: BatteryForecast.Verdict

    /// - Parameters:
    ///   - battery: The battery now.
    ///   - readings: The battery readings of the run so far.
    ///   - remaining: What is left of the workout.
    /// - Returns: `nil` while the battery is charging or unknown, or when what is left of the workout
    ///   isn't known (no workout, or an open step, which has no end).
    public init?(battery: BatteryDisplay, readings: [BatteryForecast.Reading], remaining: RemainingEstimate?) {
        guard let level = battery.level, !battery.isCharging, let remaining, remaining.isComplete else { return nil }
        let forecast = BatteryForecast(readings: readings)
        let end = forecast.level(after: remaining.seconds, from: level)
        verdict = forecast.verdict(endLevel: end)
        if verdict == .runsOut {
            let seconds = Int(min(forecast.timeUntilEmpty(from: level), 99 * 3600 + 59 * 60))
            let hours = seconds / 3600, minutes = (seconds % 3600) / 60
            text = String(format: "EMPTY IN %d:%02d", hours, minutes)
            spoken = "battery will run out in \(hours) hours \(minutes) minutes"
        } else {
            let percent = Int((end * 100).rounded())
            text = "~\(percent)% AT END"
            spoken = "about \(percent) percent at the end"
        }
    }
}
