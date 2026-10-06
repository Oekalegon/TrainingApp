import Testing
@testable import TrainingAppKit

@Suite("AthleteRoute")
struct AthleteRouteTests {
    @Test("the Watch permission banner opens Connected Services, then Apple Watch, then Synchronisation (MVP2-123)")
    func watchSettingsPath() {
        #expect(AthleteRoute.watchSettings == [.connectedServices, .appleWatch, .synchronisation])
    }

    @Test("every route has its own title and icon")
    func titlesAndIconsAreDistinct() {
        let routes: [AthleteRoute] = [
            .personalInformation, .heartRateZones, .paceZones, .connectedServices, .appleHealth,
            .appleWatch, .synchronisation, .calendar, .developer,
        ]

        #expect(Set(routes.map(\.title)).count == routes.count)
        #expect(Set(routes.map(\.systemImage)).count == routes.count)
    }
}
