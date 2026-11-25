import Foundation

/// The words for the zone histogram (WATCH-132), for VoiceOver.
public enum ZoneTimeText {
    /// "below zone 1 5 percent, zone 2 45 percent ..." for the zones holding at least half a percent, or
    /// that nothing was measured yet. `fractions` are the shares of zones 0 to 5.
    public static func spoken(_ fractions: [Double]?) -> String {
        guard let fractions else { return "no time measured yet" }
        let parts = fractions.enumerated().filter { $0.element >= 0.005 }.map { zone, fraction in
            "\(zone == 0 ? "below zone 1" : "zone \(zone)") \(Int((fraction * 100).rounded())) percent"
        }
        return parts.isEmpty ? "no time measured yet" : parts.joined(separator: ", ")
    }
}
