import TrainingWatchKit

/// The battery during a planned workout (WATCH-119): a reading every half minute for the forecast.
extension RunRecorder {
    /// How often the battery is read for the forecast, in workout seconds.
    private static let batterySampleInterval = 30.0

    /// Starts the readings of a new run.
    func resetBatteryReadings() {
        batteryReadings = []
    }

    /// Takes a battery reading if it is time for one. Called by the step ticker while running.
    func sampleBattery() {
        let time = elapsed()
        if let last = batteryReadings.last, time - last.time < Self.batterySampleInterval { return }
        guard let level = BatteryReader.current(elapsed: time).level else { return }
        batteryReadings.append(BatteryForecast.Reading(time: time, level: level))
    }

    /// The pace distances are counted at for what is left of the workout: the run's own average once it
    /// has gone a few hundred metres, otherwise 6:00 per kilometre.
    var secondsPerMeter: Double {
        distanceMeters >= 300 ? elapsed() / distanceMeters : 0.36
    }
}
