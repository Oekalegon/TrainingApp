import Foundation

/// Reads numbers out of launch arguments (the simulator's test arguments).
public enum LaunchArgument {
    /// A number from a value in `UserDefaults`. A launch argument such as `-batteryLevel 0.25` reaches
    /// the defaults as the text "0.25", not as a number, so a plain `as? Double` finds nothing.
    ///
    /// - Parameter value: What `UserDefaults.object(forKey:)` gave.
    /// - Returns: The number, or `nil` for anything that isn't one.
    public static func double(from value: Any?) -> Double? {
        switch value {
        case let number as Double: number
        case let number as NSNumber: number.doubleValue
        case let text as String: Double(text.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }
}
