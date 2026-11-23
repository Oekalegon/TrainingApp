import Testing
@testable import TrainingWatchKit

@Suite("BatteryDisplay (WATCH-118)")
struct BatteryDisplayTests {
    @Test("the level shows as a rounded percentage")
    func percent() {
        #expect(BatteryDisplay(level: 0.87, isCharging: false).percentText == "87%")
        #expect(BatteryDisplay(level: 1, isCharging: false).percentText == "100%")
        #expect(BatteryDisplay(level: 0, isCharging: false).percentText == "0%")
        #expect(BatteryDisplay(level: 1.4, isCharging: false).percentText == "100%")
    }

    @Test("an unknown level (the simulator's -1) shows as dashes, neutral and not low")
    func unknown() {
        let battery = BatteryDisplay(level: -1, isCharging: false)
        #expect(battery.percentText == "--%")
        #expect(battery.isLow == false)
        #expect(battery.symbolName == "battery.0percent")
        #expect(battery.spokenText == "Battery level unknown")
    }

    @Test("20% or less is low, unless the watch is charging")
    func low() {
        #expect(BatteryDisplay(level: 0.2, isCharging: false).isLow)
        #expect(!BatteryDisplay(level: 0.21, isCharging: false).isLow)
        #expect(!BatteryDisplay(level: 0.1, isCharging: true).isLow)
    }

    @Test("the symbol follows the charge in quarters, and a charging battery has the bolt")
    func symbols() {
        #expect(BatteryDisplay(level: 0.05, isCharging: false).symbolName == "battery.0percent")
        #expect(BatteryDisplay(level: 0.25, isCharging: false).symbolName == "battery.25percent")
        #expect(BatteryDisplay(level: 0.5, isCharging: false).symbolName == "battery.50percent")
        #expect(BatteryDisplay(level: 0.75, isCharging: false).symbolName == "battery.75percent")
        #expect(BatteryDisplay(level: 0.95, isCharging: false).symbolName == "battery.100percent")
        #expect(BatteryDisplay(level: 0.5, isCharging: true).symbolName == "battery.100percent.bolt")
    }

    @Test("VoiceOver hears the charge, and that it is charging")
    func spoken() {
        #expect(BatteryDisplay(level: 0.87, isCharging: false).spokenText == "Battery 87 percent")
        #expect(BatteryDisplay(level: 0.4, isCharging: true).spokenText == "Battery 40 percent, charging")
    }
}
