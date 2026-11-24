import Foundation

/// The battery during a run (WATCH-110, WATCH-119): a reading every half minute for the forecast, and
/// a check every few seconds for a warning, in planned workouts and free runs alike. A warning stays until
/// the athlete dismisses it.
extension RunRecorder {
    /// How often the battery is read for the forecast, in workout seconds.
    private static let batterySampleInterval = 30.0
    /// How often the battery is checked for a warning, in seconds.
    private static let batteryCheckInterval = 5.0
    /// How often the wrist is tapped again while a warning stays, in seconds, and how many times at most: a
    /// warning that is ignored for long stays on screen, but stops buzzing.
    private static let warningRepeat = 30.0
    private static let warningRepeats = 4

    /// Starts reading and checking the battery for a new run.
    func startBatteryWatch() {
        batteryReadings = []
        plannedTypicalDuration = nil
        plannedDrainPerHour = nil
        learnedDrainPerHour = drainStore?.load().typicalDrain
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
        warningNudge?.cancel()
        batteryWarning = nil
    }

    /// Takes a reading when it is time for one, and gives a warning if the battery has got worse.
    func checkBattery() {
        guard phase == .running else { return }
        let time = elapsed()
        let battery = backend.battery(elapsed: time)
        if let level = battery.level, batteryReadings.last.map({ time - $0.time >= Self.batterySampleInterval }) ?? true {
            batteryReadings.append(BatteryForecast.Reading(time: time, level: level))
        }
        let projection = BatteryProjection(
            battery: battery, readings: batteryReadings,
            remaining: stepEngine?.remaining(progress: stepProgress(), secondsPerMeter: secondsPerMeter),
            elapsed: time, typicalDuration: plannedTypicalDuration, drainPerHour: plannedDrainPerHour ?? learnedDrainPerHour)
        if let warning = batteryWarningTracker.update(battery: battery, projection: projection, at: time) {
            show(warning)
        }
    }

    /// Shows the warning screen, which stays until the athlete dismisses it, and taps the wrist, the harder
    /// the worse, and again every half minute (four times at most) while it stays, in case the athlete didn't feel it.
    private func show(_ warning: BatteryWarning) {
        batteryWarning = warning
        playHaptic(for: warning)
        warningNudge?.cancel()
        warningNudge = Task { [weak self] in
            for _ in 0..<Self.warningRepeats {
                try? await Task.sleep(for: .seconds(Self.warningRepeat))
                guard !Task.isCancelled, let self, let warning = batteryWarning else { return }
                playHaptic(for: warning)
            }
        }
    }

    /// Plays the warning; `CueRouting` picks the haptic and tone for its level.
    private func playHaptic(for warning: BatteryWarning) {
        backend.play(.batteryWarning(warning.level))
    }

    /// Writes the battery at the start and the end of the run into the workout, when the readings show
    /// both, so the phone can learn the athlete's own drain.
    func writeBatteryMetadata() async {
        guard let metadata = WorkoutMetadata.battery(readings: batteryReadings) else { return }
        do {
            try await builder?.addMetadata(metadata)
        } catch {
            log.error("battery metadata not written: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Takes the warning screen away: the athlete tapped it.
    public func dismissBatteryWarning() {
        warningNudge?.cancel()
        batteryWarning = nil
    }

    /// The pace distances are counted at for what is left of the workout: the run's own average once it
    /// has gone a few hundred metres, otherwise 6:00 per kilometre.
    public var secondsPerMeter: Double {
        distanceMeters >= 300 ? elapsed() / distanceMeters : 0.36
    }
}
