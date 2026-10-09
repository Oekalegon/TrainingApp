import TrainingCore

extension TrainingModel {
    /// Every template the athlete can plan from (MVP2-140): the built-in library, then their own
    /// templates by name. What the planned-workout sheet, the Library tab and the calendar export use.
    public var libraryTemplates: [WorkoutTemplate] {
        BuiltInWorkoutTemplates.all + templates.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
