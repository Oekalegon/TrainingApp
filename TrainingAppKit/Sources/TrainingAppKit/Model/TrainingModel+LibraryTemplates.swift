import TrainingCore

extension TrainingModel {
    /// The athlete's own templates that are still offered, by name (MVP2-140). Leaves out the ones
    /// archived because plans still use them (MVP2-142).
    public var activeTemplates: [WorkoutTemplate] {
        templates.filter { !$0.isArchived }.sortedByName()
    }

    /// Every template the athlete can plan from: the built-in library, then their own by name. What the
    /// planned-workout sheet's picker and the Library tab offer.
    public var libraryTemplates: [WorkoutTemplate] {
        BuiltInWorkoutTemplates.all + activeTemplates
    }

    /// Every template a plan's workout may have been made from: ``libraryTemplates`` plus the archived
    /// ones. What editing a plan's parameters and the calendar export look templates up in, so a
    /// template the athlete deleted but plans still use isn't lost to them (MVP2-142).
    public var knownTemplates: [WorkoutTemplate] {
        BuiltInWorkoutTemplates.all + templates.sortedByName()
    }
}

private extension Array where Element == WorkoutTemplate {
    func sortedByName() -> [WorkoutTemplate] {
        sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
