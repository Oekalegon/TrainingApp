import Foundation
import Testing
import TrainingCore
@testable import TrainingWatchKit

@Suite("WatchZones (WATCH-102)")
struct WatchZonesTests {
    /// Resting 50, max 190: reserve 140, so the Karvonen zones start at 50 + 0.5 * 140 = 120 and
    /// each is 14 bpm wide (120-134, 134-148, 148-162, 162-176, 176-190).
    private func zones(method: HeartRateZoneMethod = .karvonen, lthr: Double? = nil) -> WatchZones {
        WatchZones(settings: HeartRateZoneSettings(
            effectiveDate: Date(timeIntervalSince1970: 0), restingHeartRateBPM: 50, maxHeartRateBPM: 190,
            lactateThresholdHeartRateBPM: lthr, zoneMethod: method))
    }

    @Test("a heart rate falls in the zone whose range holds it")
    func zoneInsideRange() {
        let zones = zones()
        #expect(zones.zone(forHeartRate: 125) == 1)
        #expect(zones.zone(forHeartRate: 140) == 2)
        #expect(zones.zone(forHeartRate: 155) == 3)
        #expect(zones.zone(forHeartRate: 170) == 4)
        #expect(zones.zone(forHeartRate: 185) == 5)
    }

    @Test("a boundary belongs to the zone above it")
    func boundaries() {
        let zones = zones()
        #expect(zones.zone(forHeartRate: 120) == 1)
        #expect(zones.zone(forHeartRate: 134) == 2)
        #expect(zones.zone(forHeartRate: 176) == 5)
    }

    @Test("below zone 1 is zone 0 and above zone 5 stays zone 5")
    func outsideTheScale() {
        let zones = zones()
        #expect(zones.zone(forHeartRate: 60) == 0)
        #expect(zones.zone(forHeartRate: 119.9) == 0)
        #expect(zones.zone(forHeartRate: 200) == 5)
    }

    @Test("the bpm range of each zone matches the phone's model, and an invalid zone has none")
    func ranges() {
        let zones = zones()
        let model = HeartRateZoneModel(settings: zones.settings)
        for zone in 1...5 { #expect(zones.bpmRange(of: zone) == model.zoneBPMRange(zone)) }
        #expect(zones.bpmRange(of: 0) == nil)
        #expect(zones.bpmRange(of: 6) == nil)
    }

    @Test("the bands agree with the zone lookup and give each zone's range")
    func bands() throws {
        let zones = zones()
        let bands = try #require(ZoneBands(zones: zones))
        for bpm in stride(from: 40.0, through: 200.0, by: 3.5) { #expect(bands.zone(forHeartRate: bpm) == zones.zone(forHeartRate: bpm)) }
        for zone in 1...5 { #expect(bands.range(of: zone) == zones.bpmRange(of: zone)) }
        #expect(bands.range(of: 0) == nil)
        #expect(bands.range(of: 6) == nil)
        #expect(ZoneBands(zones: self.zones(method: .lactateThreshold, lthr: nil)) == nil)
    }

    @Test("the lactate threshold method without a threshold has no zones")
    func lactateThresholdWithoutThreshold() {
        let zones = zones(method: .lactateThreshold, lthr: nil)
        #expect(zones.zone(forHeartRate: 150) == nil)
        #expect(zones.bpmRange(of: 3) == nil)
    }

    @Test("the lactate threshold method uses the threshold's zones")
    func lactateThreshold() {
        let zones = zones(method: .lactateThreshold, lthr: 170)
        let model = HeartRateZoneModel(settings: zones.settings)
        let zone3 = model.zoneBPMRange(3)!
        #expect(zones.zone(forHeartRate: (zone3.lowerBound + zone3.upperBound) / 2) == 3)
    }

    @Test("zones survive the trip through an application context")
    func contextRoundTrip() throws {
        let zones = zones()
        let context = try zones.applicationContext()
        #expect(WatchZones(applicationContext: context) == zones)
    }

    @Test("a context without zones, or with unreadable ones, gives none")
    func contextWithoutZones() {
        #expect(WatchZones(applicationContext: [:]) == nil)
        #expect(WatchZones(applicationContext: ["heartRateZones": Data("not json".utf8)]) == nil)
        #expect(WatchZones(applicationContext: ["heartRateZones": "text"]) == nil)
    }
}

@MainActor
@Suite("WatchZoneStore (WATCH-102)")
struct WatchZoneStoreTests {
    private func freshDefaults() -> UserDefaults {
        let name = "WatchZoneStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func zones(max: Double) -> WatchZones {
        WatchZones(settings: HeartRateZoneSettings(
            effectiveDate: Date(timeIntervalSince1970: 0), restingHeartRateBPM: 50, maxHeartRateBPM: max))
    }

    @Test("a new store has no zones until some arrive")
    func startsEmpty() {
        #expect(WatchZoneStore(cache: WatchZonesCache(defaults: freshDefaults())).zones == nil)
    }

    @Test("received zones are used and are still there at the next launch")
    func keepsReceivedZones() {
        let defaults = freshDefaults()
        let store = WatchZoneStore(cache: WatchZonesCache(defaults: defaults))
        store.update(zones(max: 190))
        #expect(store.zones == zones(max: 190))
        #expect(WatchZoneStore(cache: WatchZonesCache(defaults: defaults)).zones == zones(max: 190))
    }

    @Test("zones used without persisting are gone at the next launch")
    func notPersisted() {
        let defaults = freshDefaults()
        let store = WatchZoneStore(cache: WatchZonesCache(defaults: defaults))
        store.update(zones(max: 190), persist: false)
        #expect(store.zones == zones(max: 190))
        #expect(store.bands != nil)
        #expect(WatchZoneStore(cache: WatchZonesCache(defaults: defaults)).zones == nil)
    }

    @Test("the store's bands follow its zones")
    func bandsFollowZones() {
        let store = WatchZoneStore(cache: WatchZonesCache(defaults: freshDefaults()))
        #expect(store.bands == nil)
        store.update(zones(max: 190))
        #expect(store.bands?.zone(forHeartRate: 140) == 2)
        store.update(zones(max: 160))
        #expect(store.bands?.zone(forHeartRate: 140) == 4)
    }

    @Test("newer zones replace the older ones, in the store and in the cache")
    func newerReplacesOlder() {
        let defaults = freshDefaults()
        let store = WatchZoneStore(cache: WatchZonesCache(defaults: defaults))
        store.update(zones(max: 190))
        store.update(zones(max: 185))
        #expect(store.zones == zones(max: 185))
        #expect(WatchZonesCache(defaults: defaults).load() == zones(max: 185))
    }
}
