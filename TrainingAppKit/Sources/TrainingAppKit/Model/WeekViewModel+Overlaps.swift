import Foundation
import TrainingCore

/// `WeekViewModel`'s overlap, join and delete surface (MVP1-63/65/67/80), split out of
/// `WeekViewModel.swift` to keep that file manageable.
extension WeekViewModel {
    /// `activity.id` → the overlap issue worth warning about, for every activity named by a real
    /// (non-``OverlapRecommendation/possibleMultisport``) advice — one pass over
    /// ``TrainingModel/overlapAdvice`` rather than the N passes ``overlapWarning(for:)`` would need
    /// re-filtering it per activity. `TrainingModel.overlapAdvice` itself reruns
    /// `ActivityOverlapChecker.findOverlaps(in:)` on every access (its own doc comment warns a
    /// SwiftUI-`body` caller to cache it), and `DayActivitiesSection` calls ``overlapWarning(for:)``
    /// once per activity card while building the day list — the same `body`-during-swipe path
    /// `sportStatsPagesCaches`/`weekGraphCaches` already exist to keep MVP1-19's freeze from
    /// recurring, so batching this into a single dictionary build per access is worth doing even
    /// though `ActivityOverlapChecker` itself is cheap at today's realistic activity counts.
    private var overlapWarningsByActivityID: [UUID: OverlapRecommendation] {
        var result: [UUID: OverlapRecommendation] = [:]
        for advice in model.overlapAdvice {
            if case .possibleMultisport = advice.recommendation { continue }
            for id in [advice.first, advice.second] {
                // An activity can be named by several pairs (e.g. a session split in three: A–B and
                // B–C are both joins); keep the highest-priority one rather than whichever the
                // checker happened to emit first, so the badge is stable.
                if let existing = result[id], existing.priority <= advice.recommendation.priority { continue }
                result[id] = advice.recommendation
            }
        }
        return result
    }

    /// The overlap issue worth warning about for `activity`, if any (MVP1-63) — skips
    /// ``OverlapRecommendation/possibleMultisport``: that case describes activities that
    /// legitimately sit close together (e.g. a triathlon's separately-logged legs) rather than a
    /// problem, so it isn't surfaced as a warning; `.duplicate`/`.merge`/`.conflict` all are.
    public func overlapWarning(for activity: Activity) -> OverlapRecommendation? {
        overlapWarningsByActivityID[activity.id]
    }

    /// `activity`'s overlap context — its recommendation plus the specific other activity it
    /// overlaps with — for the activity detail sheet's resolution UI (MVP1-63). Unlike
    /// ``overlapWarning(for:)``, this doesn't skip ``OverlapRecommendation/possibleMultisport``:
    /// the detail sheet is where all four recommendation types are meant to surface distinctly
    /// (MVP1-29), even the ones that don't need a delete action.
    public func overlapContext(for activity: Activity) -> OverlapContext? {
        var best: OverlapContext?
        for advice in model.overlapAdvice where advice.first == activity.id || advice.second == activity.id {
            let otherID = advice.first == activity.id ? advice.second : advice.first
            guard let other = model.activities.first(where: { $0.id == otherID }) else { continue }
            // Highest-priority pair wins, so a real issue (or a join) is never hidden behind a
            // possibleMultisport pairing that merely sorted earlier.
            if let best, best.recommendation.priority <= advice.recommendation.priority { continue }
            best = OverlapContext(recommendation: advice.recommendation, otherActivity: other)
        }
        return best
    }

    /// One row per activity worth reviewing for an overlap issue (MVP1-63) — every activity named
    /// by a non-``OverlapRecommendation/possibleMultisport`` advice, deduplicated (an activity
    /// appearing in more than one pair lists once, under its highest-priority pairing) and sorted
    /// by start time. Backs the sheet the import summary banner opens onto.
    public var overlapReviewItems: [OverlapReviewItem] {
        // Built from the same dictionary as the card badges, so a row's label always matches the
        // badge on that activity's card (both pick the highest-priority pairing).
        let warnings = overlapWarningsByActivityID
        return model.activities
            .compactMap { activity in
                warnings[activity.id].map { OverlapReviewItem(activity: activity, recommendation: $0) }
            }
            .sorted { $0.activity.start < $1.activity.start }
    }

    /// How many activities currently have an overlap issue worth reviewing (MVP1-67) — the same
    /// live count ``overlapReviewItems`` lists, surfaced as a plain `Int` for the Athlete tab's
    /// warning banner and its tab-bar badge. Always current: unlike the one-time
    /// `overlapImportSummary` snapshot this replaced, it reflects whatever `model.overlapAdvice`
    /// says right now, so resolving an overlap (``resolveOverlap(deleting:)``) updates both
    /// surfaces the moment the delete lands, with no separate "refresh the summary" step needed.
    public var overlapWarningCount: Int {
        overlapReviewItems.count
    }

    /// Resolves one side of an overlap by deleting it (MVP1-63) — the activity detail sheet's
    /// action for ``OverlapRecommendation/duplicate(keep:remove:)``/``OverlapRecommendation/merge``/
    /// ``OverlapRecommendation/conflict``: "remove this one, keep the other".
    public func resolveOverlap(deleting id: UUID, asOf today: Date = .now) async {
        await deleteActivity(id: id, asOf: today)
    }

    /// Joins `activity` and `other` — pieces of one session that was accidentally recorded in two
    /// (``OverlapRecommendation/join``, MVP1-80) — into a single activity. The originals stay
    /// stored and are only hidden behind the joined activity, so this is undone by
    /// ``unjoinActivity(_:asOf:)``. Failures fail silently, like every other store-mutating action
    /// here, but unlike those it reports whether the join happened, so the detail sheet only closes
    /// on success rather than looking as if a refused join (pieces of different sports, or one
    /// already joined elsewhere) had worked.
    ///
    /// - Returns: `true` if the activities were joined.
    @discardableResult
    public func joinActivities(_ activity: Activity, with other: Activity, asOf today: Date = .now) async -> Bool {
        do {
            try await model.joinActivities(activity.id, other.id, asOf: today)
        } catch {
            return false
        }
        await refreshWeekCachesIfNeeded()
        return true
    }

    /// Splits the joined `activity` back into the pieces it was built from (MVP1-80).
    ///
    /// - Returns: `true` if the activity was unjoined.
    @discardableResult
    public func unjoinActivity(_ activity: Activity, asOf today: Date = .now) async -> Bool {
        do {
            try await model.unjoinActivity(id: activity.id, asOf: today)
        } catch {
            return false
        }
        await refreshWeekCachesIfNeeded()
        return true
    }

    /// The pieces `activity` was joined from, earliest first, or empty if it isn't a joined
    /// activity — backs the detail sheet's "Joined from" section (MVP1-80).
    public func joinedComponents(of activity: Activity) async -> [Activity] {
        (try? await model.components(ofJoinedActivity: activity.id)) ?? []
    }

    /// The activity detail sheet's general "Delete Activity" action (MVP1-65), independent of any
    /// overlap — e.g. a bad HealthKit import the athlete just wants gone, not something
    /// ``TrainingModel/overlapAdvice`` flagged. The view gates this behind its own confirmation
    /// alert before calling it; this method itself performs the delete unconditionally.
    public func deleteActivity(_ activity: Activity, asOf today: Date = .now) async {
        await deleteActivity(id: activity.id, asOf: today)
    }

    /// Shared by ``resolveOverlap(deleting:)`` and ``deleteActivity(_:asOf:)`` — both ultimately
    /// just delete one activity by id (MVP1-64's soft-delete/tombstone semantics live entirely in
    /// `TrainingModel.deleteActivity(id:asOf:)` itself, not here). Failures fail silently, same as
    /// every other store-mutating action here — MVP 1 has no error UI.
    private func deleteActivity(id: UUID, asOf today: Date) async {
        try? await model.deleteActivity(id: id, asOf: today)
        await refreshWeekCachesIfNeeded()
    }
}
