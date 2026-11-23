import Foundation
import TrainingWatchKit
import WatchKit

/// Reads the watch's battery (WATCH-118, WATCH-119). watchOS has no notification for it, so it is read
/// when it is needed. The simulator reports no level, which shows as an empty grey bar, unless an
/// argument asks for one:
/// - `-fakeBattery`: drains from 100% to 0% every two minutes of the run, through every colour;
/// - `-batteryLevel 0.15`: holds a level (0 to 1);
/// - `-batteryDrainPerHour 0.6`: drains steadily from `-batteryLevel` (80% without it) at that share of
///   the full charge per hour, so the forecast can be tested: a 5 minute run at 0.6 drops 5%.
enum BatteryReader {
    static func current(elapsed: TimeInterval) -> BatteryDisplay {
        #if targetEnvironment(simulator)
        let defaults = UserDefaults.standard
        if let perHour = LaunchArgument.double(from: defaults.object(forKey: "batteryDrainPerHour")) {
            let start = LaunchArgument.double(from: defaults.object(forKey: "batteryLevel")) ?? 0.8
            return BatteryDisplay(level: Float(max(start - perHour * max(elapsed, 0) / 3600, 0)), isCharging: false)
        }
        if let level = LaunchArgument.double(from: defaults.object(forKey: "batteryLevel")) {
            return BatteryDisplay(level: Float(level), isCharging: false)
        }
        if CommandLine.arguments.contains("-fakeBattery") {
            return BatteryDisplay(level: BatteryDisplay.simulatedLevel(elapsed: elapsed), isCharging: false)
        }
        #endif
        let device = WKInterfaceDevice.current()
        return BatteryDisplay(
            level: device.batteryLevel, isCharging: device.batteryState == .charging || device.batteryState == .full)
    }
}
