import Foundation
import TrainingCore

/// Where the athlete's preferred run types per micro day and micro length are kept (MVP5-112), on this device.
///
/// An interim store: `AthleteProfile` has no run type field in TrainingKit yet, so the choice is kept in
/// `UserDefaults` and does not sync. When TrainingKit gains an athlete-level `dayRunTypes`, this is replaced by
/// the profile, like `runAvailability`.
@MainActor
struct AthleteRunTypesStore {
    private let defaults: UserDefaults
    private let preferencesKey = "athleteRunTypes.preferences"
    private let lengthKey = "athleteRunTypes.microLength"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// The saved run types (as `PlanPreferences`, whose decoding rules apply) and micro length (7 if none was saved).
    func load() -> (preferences: PlanPreferences, microLength: Int) {
        let preferences = defaults.data(forKey: preferencesKey)
            .flatMap { try? JSONDecoder().decode(PlanPreferences.self, from: $0) } ?? PlanPreferences()
        let length = defaults.integer(forKey: lengthKey)
        return (preferences, RunTypePickerViewModel.supportedMicroLengths.contains(length) ? length : 7)
    }

    /// Saves the run types, including days beyond the micro length, which a longer length brings back.
    func save(_ preferences: PlanPreferences, microLength: Int) {
        defaults.set(try? JSONEncoder().encode(preferences), forKey: preferencesKey)
        defaults.set(microLength, forKey: lengthKey)
    }
}
