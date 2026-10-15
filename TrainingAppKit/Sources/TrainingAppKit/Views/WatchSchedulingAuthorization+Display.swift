extension WatchSchedulingAuthorization {
    /// The Athlete tab's Watch Permission row (MVP2-117), e.g. "Not allowed".
    var statusText: String {
        switch self {
        case .authorized: "Allowed"
        case .notDetermined: "Not asked yet"
        case .denied: "Not allowed"
        case .unavailable: "Unavailable"
        }
    }

    /// The footer under that status: what it means, and for `.denied` where to turn it back on,
    /// since iOS doesn't ask again and the app can't turn it on itself.
    ///
    /// - Parameter isEnabled: Whether the athlete has the app's "Send Planned Workouts to Apple
    ///   Watch" switch on (MVP2-118). While it's off, the footer says so instead, whatever the
    ///   permission; a device that can't schedule workouts shows no switch, so it keeps its own text.
    func explanation(isEnabled: Bool) -> String {
        if !isEnabled, self != .unavailable {
            return "Planned workouts aren't sent to your Apple Watch. Turn this on to have each planned workout ready in the Workout app on the day it's due."
        }
        return switch self {
        case .authorized:
            "The next 7 days of planned workouts are kept in the Workout app on your Apple Watch, each ready on the day it's due."
        case .notDetermined:
            "Allow this app to schedule workouts to have each planned workout ready in the Workout app on your Apple Watch on the day it's due."
        case .denied:
            "Planned workouts aren't sent to your Apple Watch. iOS asks only once, so turn it back on yourself: open the Watch app on your iPhone, tap Workout, and turn this app on."
        case .unavailable:
            "This iPhone can't schedule workouts on an Apple Watch."
        }
    }
}
