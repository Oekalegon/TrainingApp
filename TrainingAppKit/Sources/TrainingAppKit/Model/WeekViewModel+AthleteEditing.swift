import Foundation
import TrainingCore

/// The athlete's own changes to their profile (MVP2-132), from the Athlete tab's screens. Each goes
/// through `TrainingModel.updateAthlete(asOf:_:)`, which saves before it assigns, queues behind
/// imports and other updates, and invalidates the fitness-metrics cache from the earliest changed
/// date; so a failed save changes nothing and these report it by returning `false`.
extension WeekViewModel {
    /// Renames the athlete. Surrounding whitespace is dropped, and an empty name is allowed: the
    /// screens then show "Athlete".
    ///
    /// - Returns: Whether the profile was saved.
    public func setAthleteName(_ name: String, asOf today: Date = .now) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return await applyAthleteChange(asOf: today) { $0.name = trimmed }
    }

    /// Records heart-rate settings from a date, replacing the entry for that day.
    ///
    /// - Parameter settings: Resting and maximum heart rate, lactate threshold and zone method.
    /// - Returns: Whether the profile was saved.
    public func recordHeartRateSettings(_ settings: HeartRateZoneSettings, asOf today: Date = .now) async -> Bool {
        await applyAthleteChange(asOf: today) { $0.recordingHeartRateSettings(settings) }
    }

    /// Removes the heart-rate settings entry for a day; the last entry stays.
    ///
    /// - Returns: Whether the profile was saved.
    public func removeHeartRateSettings(on date: Date, asOf today: Date = .now) async -> Bool {
        await applyAthleteChange(asOf: today) { $0.removingHeartRateSettings(on: date) }
    }

    /// Records a threshold pace from a date, keeping the zone multipliers of the model in effect then.
    ///
    /// - Parameters:
    ///   - thresholdPaceSecondsPerKilometer: The pace, in seconds per kilometer.
    ///   - date: The day it takes effect.
    /// - Returns: Whether the profile was saved.
    public func recordThresholdPace(
        secondsPerKilometer thresholdPaceSecondsPerKilometer: Double, from date: Date, asOf today: Date = .now
    ) async -> Bool {
        await applyAthleteChange(asOf: today) { athlete in
            let base = athlete.paceModel(asOf: date)
            return athlete.recordingPaceModel(
                PaceModel(
                    thresholdPaceSecondsPerKilometer: thresholdPaceSecondsPerKilometer,
                    zonePaceMultipliers: base.zonePaceMultipliers
                ),
                from: date
            )
        }
    }

    /// Removes the pace entry for a day; the last entry stays.
    ///
    /// - Returns: Whether the profile was saved.
    public func removePaceSettings(on date: Date, asOf today: Date = .now) async -> Bool {
        await applyAthleteChange(asOf: today) { $0.removingPaceSettings(on: date) }
    }

    /// Turns following HealthKit's resting heart rate on or off. Turning it on imports straight away,
    /// so the reading applies without waiting for the next refresh.
    ///
    /// - Returns: Whether the profile was saved.
    public func setUsesHealthKitRestingHeartRate(_ isOn: Bool, asOf today: Date = .now) async -> Bool {
        let saved = await applyAthleteChange(asOf: today) { $0.usesHealthKitRestingHeartRate = isOn }
        if saved, isOn {
            await refresh(asOf: today)
        }
        return saved
    }

    /// Changes the day the week starts on. The displayed week moves to the one that contains it under
    /// the new start, and everything is reloaded: weekly statistics regroup, and the fitness history
    /// is rebuilt.
    ///
    /// - Returns: Whether the profile was saved.
    public func setWeekStartsOn(_ weekday: Weekday, asOf today: Date = .now) async -> Bool {
        let saved = await applyAthleteChange(asOf: today) { $0.weekStartsOn = weekday }
        if saved { await realignAfterCalendarChange(asOf: today) }
        return saved
    }

    /// Changes the time zone every day is grouped by. The displayed week moves to the one that
    /// contains it in the new zone, and everything is reloaded: days and weeks regroup, and the whole
    /// fitness history is rebuilt (once).
    ///
    /// - Returns: Whether the profile was saved.
    public func setTimeZone(_ timeZone: TimeZone, asOf today: Date = .now) async -> Bool {
        let saved = await applyAthleteChange(asOf: today) { $0.timeZone = timeZone }
        if saved { await realignAfterCalendarChange(asOf: today) }
        return saved
    }

    /// Runs `change` on the current profile through `TrainingModel.updateAthlete`.
    private func applyAthleteChange(
        asOf today: Date, _ change: @escaping @Sendable (AthleteProfile) -> AthleteProfile
    ) async -> Bool {
        do {
            try await model.updateAthlete(asOf: today, change)
            return true
        } catch {
            return false
        }
    }

    /// `applyAthleteChange` for a change made in place.
    private func applyAthleteChange(
        asOf today: Date, _ change: @escaping @Sendable (inout AthleteProfile) -> Void
    ) async -> Bool {
        await applyAthleteChange(asOf: today) { athlete in
            var athlete = athlete
            change(&athlete)
            return athlete
        }
    }

    /// Keeps the displayed week on the day it showed, under a changed time zone or week start, then
    /// loads around it.
    private func realignAfterCalendarChange(asOf today: Date) async {
        goToWeek(containing: displayedWeekStart)
        await load(asOf: today)
    }
}
