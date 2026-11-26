import Foundation

/// The two sample runs the preview draws from, made once: a free run and a planned workout (WATCH-138).
@MainActor
enum SampleRuns {
    static let free = SampleRunScreenSource(isWorkout: false)
    static let workout = SampleRunScreenSource(isWorkout: true)
}
