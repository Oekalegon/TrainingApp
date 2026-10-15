import Foundation

extension Notification.Name {
    /// Posted after workouts that reached Health on their own (MVP2-121) were imported in the
    /// background, so a running UI can refresh the caches an import normally refreshes itself.
    public static let trainingAppDidImportWorkouts = Notification.Name("TrainingAppDidImportWorkouts")
}
