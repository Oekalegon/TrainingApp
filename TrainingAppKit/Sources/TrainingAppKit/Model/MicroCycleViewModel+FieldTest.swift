import Foundation
import TrainingCore

/// Asking the athlete to update their max heart rate or lactate threshold heart rate after a field
/// test (MVP2-155).
///
/// The same shape as the max heart rate suggestion (MVP2-56): TrainingKit measures the result, the
/// athlete confirms, and only then are the settings changed, since a new value moves every zone and
/// training-load score from the test's day on. Unlike that suggestion, a max heart rate from a test may
/// be lower than the one on record.
extension MicroCycleViewModel {
    /// Looks through the loaded activities for a field test whose result the athlete hasn't answered
    /// yet and, if one is found, sets ``fieldTestResult`` for `MicroCycleView` to ask about.
    ///
    /// Only activities linked to a plan whose workout is a test are measured. Skipped: activities
    /// already declined, and those whose result is already the source of the athlete's max heart rate
    /// or lactate threshold. A result equal to the value on record is still offered, since accepting it
    /// replaces an estimate's source with the measured one, unless that would replace a more reliable
    /// source such as a lab test. A test that can't be measured (no heart
    /// rate, the effort not found, ...) is skipped without an alert; its reason is kept in
    /// ``fieldTestFailures`` for the activity's detail sheet (MVP2-157), and it isn't tried again until
    /// the next import.
    ///
    /// Does nothing while a result is already waiting, or while an accepted one is still being saved
    /// (see ``isApplyingFieldTest``). Called with the max heart rate check, after every import and
    /// whenever the week view loads a week.
    public func checkForFieldTestResult() async {
        guard fieldTestResult == nil, !isApplyingFieldTest else { return }
        let declined = maxHeartRatePromptHistory.declinedActivityIDs
        let applied = appliedFieldTestActivityIDs
        for activity in model.activities.sorted(by: { $0.start > $1.start })
        where activity.linkedPlanID != nil && !declined.contains(activity.id) && !applied.contains(activity.id)
            && fieldTestFailures[activity.id] == nil && mayBeFieldTest(activity) {
            let result: FieldTestResult?
            do {
                result = try await model.fieldTestResult(forActivity: activity.id)
            } catch let error as FieldTestError {
                fieldTestFailures[activity.id] = error
                continue
            } catch {
                // A store failure may pass; the next check tries again.
                continue
            }
            // An equal value over a more reliable source (a lab test) would only swap in a weaker
            // source, so there's nothing to ask (MVP2-158).
            guard let result, !(result.currentBPM == result.valueBPM && result.replacesMoreReliableSource) else { continue }
            // The athlete may have answered, or another check set one, while this one was measuring.
            guard fieldTestResult == nil, !isApplyingFieldTest else { return }
            fieldTestResult = result
            return
        }
    }

    /// Whether `activity`'s plan is for a test, judged from the loaded plans and workouts so that
    /// ordinary linked workouts don't each cost a store read. A plan or workout that isn't loaded
    /// counts as possibly a test; the model then decides.
    private func mayBeFieldTest(_ activity: Activity) -> Bool {
        guard let plan = model.plans.first(where: { $0.id == activity.linkedPlanID }),
              let workout = model.workouts.first(where: { $0.id == plan.workoutID }) else { return true }
        return workout.purpose != .general
    }

    /// The activities whose field-test result is already recorded as a source in the athlete's
    /// heart-rate settings.
    private var appliedFieldTestActivityIDs: Set<UUID> {
        var ids: Set<UUID> = []
        for settings in model.athlete.heartRateZoneHistory {
            if case .fieldTest(let id) = settings.maxHeartRateSource { ids.insert(id) }
            if case .fieldTest(let id) = settings.lactateThresholdSource { ids.insert(id) }
        }
        return ids
    }

    /// Records `result` as the athlete's max heart rate or lactate threshold heart rate from the test's
    /// day onward, then refreshes the week's cached figures.
    ///
    /// Takes the result explicitly, like ``acceptMaxHeartRateSuggestion(_:asOf:)``, because the alert
    /// clears ``fieldTestResult`` when it dismisses. On a failed save nothing changes and
    /// ``fieldTestUpdateFailed`` is set; the test isn't recorded as declined, so the next check asks again.
    ///
    /// - Parameters:
    ///   - result: The result the athlete accepted.
    ///   - today: Passed through to the recompute.
    public func acceptFieldTestResult(_ result: FieldTestResult, asOf today: Date = .now) async {
        clearFieldTestPrompt()
        isApplyingFieldTest = true
        defer { isApplyingFieldTest = false }
        do {
            try await model.applyFieldTestResult(result, asOf: today)
        } catch {
            fieldTestUpdateFailed = true
            return
        }
        await refreshPeriodCachesIfNeeded(asOf: today)
    }

    /// Keeps the old value: records the test's activity as declined, so it isn't asked about again,
    /// and dismisses the prompt.
    ///
    /// - Parameter result: The result the athlete declined.
    public func declineFieldTestResult(_ result: FieldTestResult) {
        maxHeartRatePromptHistory.declinedActivityIDs.insert(result.activityID)
        clearFieldTestPrompt()
    }

    /// Dismisses the prompt without accepting or declining, e.g. when the alert closes. The result
    /// comes back on the next check.
    public func clearFieldTestPrompt() {
        fieldTestResult = nil
    }

    /// Clears ``fieldTestUpdateFailed`` once `MicroCycleView` has shown it.
    public func acknowledgeFieldTestUpdateFailure() {
        fieldTestUpdateFailed = false
    }

    /// The alert's title: which setting the test measured.
    ///
    /// - Parameter result: The result to describe.
    public func fieldTestPromptTitle(for result: FieldTestResult) -> String {
        switch result.measurement {
        case .maxHeartRate: "New Max Heart Rate?"
        case .lactateThresholdHeartRate: "New Lactate Threshold?"
        }
    }

    /// The label of the accepting button, e.g. "Update to 189 bpm".
    ///
    /// - Parameter result: The result to describe.
    public func fieldTestAcceptTitle(for result: FieldTestResult) -> String {
        if result.currentBPM == result.valueBPM { return "Record \(Int(result.valueBPM)) bpm" }
        return "Update to \(Int(result.valueBPM)) bpm"
    }

    /// The question `MicroCycleView`'s alert asks about `result`, e.g. "Your max heart rate test on 24 Sep
    /// measured 171 bpm, below your max heart rate of 178 bpm. …".
    ///
    /// - Parameter result: The result to describe.
    /// - Returns: The alert's message.
    public func fieldTestPromptMessage(for result: FieldTestResult) -> String {
        let date = result.activityStart.formatted(
            Date.FormatStyle(calendar: athleteCalendar, timeZone: athleteTimeZone).day().month(.abbreviated)
        )
        let value = Int(result.valueBPM)
        let setting: String
        let test: String
        switch result.measurement {
        case .maxHeartRate:
            setting = "max heart rate"
            test = "max heart rate test"
        case .lactateThresholdHeartRate:
            setting = "lactate threshold heart rate"
            test = "lactate threshold test"
        }
        var message = "We measured \(value) bpm in your \(test) on \(date)"
        if let current = result.currentBPM, current == result.valueBPM {
            return message + ", the same as your \(setting). Record it as measured? "
                + "Your zones and training load stay as they are."
        } else if let current = result.currentBPM {
            let currentBPM = Int(current.rounded())
            let comparison = result.valueBPM > current ? "above" : "below"
            message += ", \(comparison) your \(setting) of \(currentBPM) bpm."
        } else {
            message += "; you have no \(setting) on record."
        }
        message += " Update your \(setting) to \(value) bpm? "
            + "Your zones and training load from that day on will be recalculated."
        if result.replacesMoreReliableSource {
            let note = switch result.measurement {
            case .maxHeartRate: replacedMaxSourceNote(at: result.activityStart)
            case .lactateThresholdHeartRate: replacedLactateSourceNote(at: result.activityStart)
            }
            message += note
        }
        if result.isEstimatedFromPlan {
            message += " The test wasn't started from its scheduled workout, so the effort was placed "
                + "by the plan's timing; check that it looks right."
        }
        return message
    }

    /// A sentence for an alert that would replace a more reliable max heart rate than it measured,
    /// e.g. " This replaces a lab-tested value." (MVP2-158); empty when the value in effect on `date`
    /// isn't a lab or field test. TrainingKit says whether a result replaces a more reliable source
    /// (`replacesMoreReliableSource`); this names it, from the profile as of the activity (which can
    /// differ from the one TrainingKit checked if the profile changed since, in which case the note may
    /// name a different source than the one replaced).
    ///
    /// - Parameter date: The start of the activity whose value would be replaced.
    func replacedMaxSourceNote(at date: Date) -> String {
        guard let source = model.athlete.heartRateZoneSettings(asOf: date)?.maxHeartRateSource else { return "" }
        switch source {
        case .labTest: return " This replaces a lab-tested value."
        case .fieldTest: return " This replaces a field-tested value."
        case .formula, .manual, .workout: return ""
        }
    }

    /// The same for a lactate threshold heart rate (MVP2-158).
    ///
    /// - Parameter date: The start of the activity whose value would be replaced.
    func replacedLactateSourceNote(at date: Date) -> String {
        guard let source = model.athlete.heartRateZoneSettings(asOf: date)?.lactateThresholdSource else { return "" }
        switch source {
        case .labTest: return " This replaces a lab-tested value."
        case .fieldTest: return " This replaces a field-tested value."
        case .manual: return ""
        }
    }
}
