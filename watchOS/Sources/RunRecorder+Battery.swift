import TrainingWatchKit
import WatchKit

/// The battery during a run (WATCH-110, WATCH-119): a reading every half minute for the forecast, and
/// a check every few seconds for a warning, in planned workouts and free runs alike.
extension RunRecorder {
    /// How often the battery is read for the forecast, in workout seconds.
    private static let batterySampleInterval = 30.0
    /// How often the battery is checked for a warning, in seconds.
    private static let batteryCheckInterval = 5.0
    /// How long the warning screen stays, in seconds.
    private static let warningDuration = 10.0

    /// Starts reading and checking the battery for a new run.
    func startBatteryWatch() {
        batteryReadings = []
        batteryWarningTracker = BatteryWarningTracker()
        batteryWarning = nil
        batteryTicker?.cancel()
        batteryTicker = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkBattery()
                try? await Task.sleep(for: .seconds(Self.batteryCheckInterval))
            }
        }
    }

    /// Stops reading the battery, when the run is over, and takes the warning screen away.
    func stopBatteryWatch() {
        batteryTicker?.cancel()
        batteryTicker = nil
        warningTimer?.cancel()
        batteryWarning = nil
    }

    /// Takes a reading when it is time for one, and gives a warning if the battery has got worse.
    private func checkBattery() {
        guard phase == .running else { return }
        let time = elapsed()
        let battery = BatteryReader.current(elapsed: time)
        if let level = battery.level, batteryReadings.last.map({ time - $0.time >= Self.batterySampleInterval }) ?? true {
            batteryReadings.append(BatteryForecast.Reading(time: time, level: level))
        }
        let projection = BatteryProjection(
            battery: battery, readings: batteryReadings,
            remaining: stepEngine?.remaining(progress: stepProgress(), secondsPerMeter: secondsPerMeter))
        if let warning = batteryWarningTracker.update(battery: battery, projection: projection, at: time) {
            show(warning)
        }
    }

    /// Shows the warning screen for a few seconds and taps the wrist, the harder the worse.
    private func show(_ warning: BatteryWarning) {
        batteryWarning = warning
        // Starting values, one a level: WATCH-117 gives every signal its own pattern and tone.
        switch warning.level {
        case .tight: WKInterfaceDevice.current().play(.notification)
        case .critical: WKInterfaceDevice.current().play(.retry)
        case .runsOut: WKInterfaceDevice.current().play(.failure)
        }
        warningTimer?.cancel()
        warningTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.warningDuration))
            guard !Task.isCancelled else { return }
            self?.dismissBatteryWarning()
        }
    }

    /// Takes the warning screen away: tapped, or its time is up.
    func dismissBatteryWarning() {
        warningTimer?.cancel()
        batteryWarning = nil
    }

    /// The pace distances are counted at for what is left of the workout: the run's own average once it
    /// has gone a few hundred metres, otherwise 6:00 per kilometre.
    var secondsPerMeter: Double {
        distanceMeters >= 300 ? elapsed() / distanceMeters : 0.36
    }
}
