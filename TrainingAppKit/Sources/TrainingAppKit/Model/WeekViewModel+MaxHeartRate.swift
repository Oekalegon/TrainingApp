import Foundation
import TrainingCore

/// Asking the athlete to raise their max heart rate when a workout held a higher one (MVP2-56).
extension WeekViewModel {
    /// How far back the one-time history scan looks. Max heart rate falls with age, so a peak from
    /// years ago says little about today's max.
    static let maxHeartRateHistoryScanDays = 365

    /// Looks for a workout that held a heart rate above the athlete's current max and, if one is
    /// found, sets ``maxHeartRateSuggestion`` for `WeekView` to ask about.
    ///
    /// Checks the loaded activities first. If it finds nothing there, it also scans the last
    /// ``maxHeartRateHistoryScanDays`` days in the store, once per device. The scan waits until
    /// the first HealthKit import has completed (`TrainingModel.hasEverImportedActivities`): on a
    /// fresh install the store starts empty, and a scan then would find nothing and never run
    /// again. Declined activities are skipped.
    ///
    /// Does nothing while a suggestion is already waiting, or while an accepted one is still being
    /// saved (see ``isApplyingMaxHeartRate``). Called after every import and whenever the week
    /// view loads a week.
    ///
    /// - Parameter today: The end of the history scan's range.
    public func checkForMaxHeartRateSuggestion(asOf today: Date = .now) async {
        guard maxHeartRateSuggestion == nil, !isApplyingMaxHeartRate else { return }
        let declined = maxHeartRatePromptHistory.declinedActivityIDs
        if let suggestion = model.maxHeartRateSuggestion(among: model.activities.filter { !declined.contains($0.id) }) {
            maxHeartRateSuggestion = suggestion
            return
        }
        guard !maxHeartRatePromptHistory.hasScannedHistory, model.hasEverImportedActivities else { return }
        let start = athleteCalendar.date(byAdding: .day, value: -Self.maxHeartRateHistoryScanDays, to: today) ?? today
        do {
            let suggestion = try await model.scanForMaxHeartRateSuggestion(in: start...today, excluding: declined)
            maxHeartRatePromptHistory.hasScannedHistory = true
            if maxHeartRateSuggestion == nil, !isApplyingMaxHeartRate {
                maxHeartRateSuggestion = suggestion
            }
        } catch {
            // A failed read leaves the scan to run again on the next check.
        }
    }

    /// Raises max heart rate to `suggestion`'s peak, from that workout onward, then refreshes the
    /// week's cached figures (zones and training load change with it).
    ///
    /// Takes the suggestion explicitly rather than reading ``maxHeartRateSuggestion``, because the
    /// alert clears that when it dismisses, which may happen before this runs. Checks are paused
    /// until the save finishes (``isApplyingMaxHeartRate``). On a failed save nothing changes,
    /// ``maxHeartRateUpdateFailed`` is set, and the activity isn't recorded as declined, so the
    /// next check (after an import or a week change) asks again.
    ///
    /// - Parameters:
    ///   - suggestion: The suggestion the athlete accepted.
    ///   - today: Passed through to the recompute.
    public func acceptMaxHeartRateSuggestion(_ suggestion: MaxHeartRateSuggestion, asOf today: Date = .now) async {
        clearMaxHeartRatePrompt()
        isApplyingMaxHeartRate = true
        defer { isApplyingMaxHeartRate = false }
        do {
            try await model.applyMaxHeartRate(suggestion, asOf: today)
        } catch {
            maxHeartRateUpdateFailed = true
            return
        }
        await refreshWeekCachesIfNeeded(asOf: today)
    }

    /// Records `suggestion`'s activity as declined, so it isn't suggested again, and dismisses
    /// the prompt.
    ///
    /// - Parameter suggestion: The suggestion the athlete declined.
    public func declineMaxHeartRateSuggestion(_ suggestion: MaxHeartRateSuggestion) {
        maxHeartRatePromptHistory.declinedActivityIDs.insert(suggestion.activityID)
        clearMaxHeartRatePrompt()
    }

    /// Dismisses the prompt without accepting or declining, e.g. when the alert closes. The
    /// suggestion comes back on the next check.
    public func clearMaxHeartRatePrompt() {
        maxHeartRateSuggestion = nil
    }

    /// Clears ``maxHeartRateUpdateFailed`` once `WeekView` has shown it.
    public func acknowledgeMaxHeartRateUpdateFailure() {
        maxHeartRateUpdateFailed = false
    }

    /// The question `WeekView`'s alert asks about `suggestion`, e.g. "Your running workout on 24 Sep held
    /// 189 bpm, above your max heart rate of 178 bpm. …".
    ///
    /// - Parameter suggestion: The suggestion to describe.
    /// - Returns: The alert's message.
    public func maxHeartRatePromptMessage(for suggestion: MaxHeartRateSuggestion) -> String {
        let date = suggestion.activityStart.formatted(
            Date.FormatStyle(calendar: athleteCalendar, timeZone: athleteTimeZone).day().month(.abbreviated)
        )
        let peak = Int(suggestion.peakBPM)
        let current = Int(suggestion.currentMaxBPM.rounded())
        return "Your \(suggestion.sport.displayName.lowercased()) workout on \(date) held \(peak) bpm, "
            + "above your max heart rate of \(current) bpm. Update your max heart rate to \(peak) bpm? "
            + "Your zones and training load from that day on will be recalculated."
    }
}
