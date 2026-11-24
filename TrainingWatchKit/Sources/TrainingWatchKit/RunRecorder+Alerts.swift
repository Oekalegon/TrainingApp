import Foundation

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
        lastCountdownSecond = nil
        let alert = alertEngine.beginStep(target: currentTarget, at: elapsed())
        log(alert)
        backend.play(.zoneAlert(alert))
        if let step = stepEngine?.current, announcedAheadIndex != step.index {
            backend.play(.stepAnnouncement(StepAnnouncement.text(for: step)))
        }
    }

    /// A heart-rate reading arrived. Alerts only in a planned workout, while running.
    func alertHeartRate(_ bpm: Double) {
        guard phase == .running, let engine = stepEngine, !engine.isFinished else { return }
        // Zones can arrive in the middle of a step; a step already running picks them up here.
        alertEngine.updateTarget(currentTarget)
        if let alert = alertEngine.add(bpm, at: elapsed()) {
            log(alert)
            backend.play(.zoneAlert(alert))
        }
    }

    /// The last alerts as one line for the simulator's metrics page, newest first, as "1:12 tooLow".
    public var alertLogText: String {
        alertLog.reversed().map { entry in
            let seconds = Int(entry.time)
            return "\(seconds / 60):\(String(format: "%02d", seconds % 60)) \(entry.alert)"
        }.joined(separator: "  ")
    }

    /// Keeps the last few alerts for the simulator's debug line.
    private func log(_ alert: ZoneAlert) {
        alertLog = Array((alertLog + [(elapsed(), alert)]).suffix(3))
    }
}
