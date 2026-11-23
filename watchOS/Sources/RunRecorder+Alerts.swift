import TrainingWatchKit

/// Zone alerts while a planned workout runs (WATCH-106): `ZoneAlertEngine` decides when, this feeds
/// it the steps and the heart rate and plays the haptic.
extension RunRecorder {
    /// The current step's heart-rate target against the athlete's zones, or `nil` in a free run, in
    /// a step without a heart-rate target, or before zones have arrived.
    private var currentTarget: ClosedRange<Double>? {
        guard let step = stepEngine?.current?.step else { return nil }
        return StepHeartRateTarget(step: step, bands: zoneStore?.bands)?.bpm
    }

    /// A step began (the first one, a goal reached or the lap button): resets the engine for its
    /// target and plays the step's own haptic.
    func alertStepStarted() {
        let alert = alertEngine.beginStep(target: currentTarget, at: elapsed())
        log(alert)
        ZoneAlertHaptics.play(alert)
    }

    /// A heart-rate reading arrived. Alerts only in a planned workout, while running.
    func alertHeartRate(_ bpm: Double) {
        guard phase == .running, let engine = stepEngine, !engine.isFinished else { return }
        // Zones can arrive in the middle of a step; a step already running picks them up here.
        alertEngine.updateTarget(currentTarget)
        if let alert = alertEngine.add(bpm, at: elapsed()) {
            log(alert)
            ZoneAlertHaptics.play(alert)
        }
    }

    /// Keeps the last few alerts for the simulator's debug line.
    private func log(_ alert: ZoneAlert) {
        #if targetEnvironment(simulator)
        alertLog = Array((alertLog + [(elapsed(), alert)]).suffix(3))
        #endif
    }
}
