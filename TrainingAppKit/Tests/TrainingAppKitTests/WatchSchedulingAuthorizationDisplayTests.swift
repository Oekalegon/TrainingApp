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
        #expect(WatchSchedulingAuthorization.denied.explanation.contains("Watch app"))
        #expect(WatchSchedulingAuthorization.denied.explanation.contains("Workout"))
    }
}
