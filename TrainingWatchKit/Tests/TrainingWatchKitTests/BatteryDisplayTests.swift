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

    @Test("green above 20%, yellow above 10%, orange from 5%, red under 5%")
    func bands() {
        func band(_ level: Float) -> BatteryDisplay.Band { BatteryDisplay(level: level, isCharging: false).band }
        #expect(band(1) == .good)
        #expect(band(0.21) == .good)
        #expect(band(0.2) == .low)
        #expect(band(0.11) == .low)
        #expect(band(0.1) == .veryLow)
        #expect(band(0.05) == .veryLow)
        #expect(band(0.044) == .critical)
        #expect(band(0) == .critical)
    }

    @Test("an unknown level (the simulator's -1) is neutral, with an empty bar")
    func unknown() {
        let battery = BatteryDisplay(level: -1, isCharging: false)
        #expect(battery.percentText == "--%")
        #expect(battery.band == .unknown)
        #expect(battery.spokenText == "Battery level unknown")
        for index in 0..<BatteryDisplay.segmentCount { #expect(battery.fill(ofSegment: index) == 0) }
    }

    @Test("the bar is ten parts, whole ones up to the charge and a part of the one it falls in")
    func segments() {
        let battery = BatteryDisplay(level: 0.35, isCharging: false)
        #expect(battery.fill(ofSegment: 0) == 1 && battery.fill(ofSegment: 2) == 1)
        #expect(abs(battery.fill(ofSegment: 3) - 0.5) < 0.001)
        #expect(battery.fill(ofSegment: 4) == 0 && battery.fill(ofSegment: 9) == 0)
        let full = BatteryDisplay(level: 1, isCharging: true)
        for index in 0..<BatteryDisplay.segmentCount { #expect(full.fill(ofSegment: index) == 1) }
        let empty = BatteryDisplay(level: 0, isCharging: false)
        for index in 0..<BatteryDisplay.segmentCount { #expect(empty.fill(ofSegment: index) == 0) }
    }

    @Test("VoiceOver hears the charge, and that it is charging")
    func spoken() {
        #expect(BatteryDisplay(level: 0.87, isCharging: false).spokenText == "Battery 87 percent")
        #expect(BatteryDisplay(level: 0.4, isCharging: true).spokenText == "Battery 40 percent, charging")
    }
}
