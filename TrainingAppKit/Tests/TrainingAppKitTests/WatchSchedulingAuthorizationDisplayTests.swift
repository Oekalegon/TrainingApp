import Testing
@testable import TrainingAppKit

@Suite("WatchSchedulingAuthorization+Display")
struct WatchSchedulingAuthorizationDisplayTests {
    @Test("each state has its own status")
    func statusTextsAreDistinct() {
        let states: [WatchSchedulingAuthorization] = [.authorized, .notDetermined, .denied, .unavailable]
        #expect(Set(states.map(\.statusText)).count == states.count)
    }

    @Test("a declined permission says where to turn it back on")
    func deniedPointsToWatchApp() {
        let explanation = WatchSchedulingAuthorization.denied.explanation(isEnabled: true)
        #expect(explanation.contains("Watch app"))
        #expect(explanation.contains("Workout"))
    }

    @Test("with sending turned off, the footer says so whatever the permission (MVP2-118)")
    func turnedOffExplanation() {
        let off = WatchSchedulingAuthorization.authorized.explanation(isEnabled: false)
        #expect(off.contains("aren't sent"))
        #expect(WatchSchedulingAuthorization.denied.explanation(isEnabled: false) == off)
        #expect(WatchSchedulingAuthorization.notDetermined.explanation(isEnabled: false) == off)
        #expect(
            WatchSchedulingAuthorization.unavailable.explanation(isEnabled: false)
                == WatchSchedulingAuthorization.unavailable.explanation(isEnabled: true)
        )
    }
}
