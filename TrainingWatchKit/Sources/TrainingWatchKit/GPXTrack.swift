import Foundation

/// One point of a GPX track: where and when, and the heart rate the file recorded there.
public struct GPXTrackPoint: Sendable, Hashable {
    public var time: Date
    public var latitude: Double
    public var longitude: Double
    /// In metres; 0 when the file has none.
    public var altitude: Double
    /// In beats per minute, when the file has it.
    public var heartRate: Double?

    public init(time: Date, latitude: Double, longitude: Double, altitude: Double = 0, heartRate: Double? = nil) {
        self.time = time
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.heartRate = heartRate
    }
}

/// Reads the track points out of a GPX file, for the watch simulator's replay (a simulator records
/// no location or heart rate). Reads what a Strava or Garmin export has and nothing more: points
/// need a position and a time, and a point that has neither is skipped. Kept here, away from the
/// simulator-only code that plays it, so it can be tested.
public enum GPXTrack {
    /// The points of every `<trkpt>` in `text`, in file order.
    ///
    /// The heart rate is read from the point's extensions: Garmin's track point extension
    /// (`<gpxtpx:hr>`, under whatever prefix the file gives it) or a plain `<hr>`.
    ///
    /// - Parameter text: The contents of a GPX file.
    public static func points(in text: String) -> [GPXTrackPoint] {
        let wholeSeconds = ISO8601DateFormatter()
        let fractionalSeconds = ISO8601DateFormatter()
        fractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return text.split(separator: "<trkpt").dropFirst().compactMap { chunk in
            // A point ends at its closing tag; whatever follows belongs to the file's trailer.
            let point = chunk.range(of: "</trkpt>").map { chunk[..<$0.lowerBound] } ?? chunk
            guard let latitude = attribute("lat", in: point), let longitude = attribute("lon", in: point),
                  let time = value(of: "time", in: point).flatMap({ wholeSeconds.date(from: $0) ?? fractionalSeconds.date(from: $0) })
            else { return nil }
            return GPXTrackPoint(
                time: time, latitude: latitude, longitude: longitude,
                altitude: value(of: "ele", in: point).flatMap(Double.init) ?? 0,
                heartRate: heartRate(in: point))
        }
    }

    private static func value(of tag: String, in chunk: Substring) -> String? {
        guard let open = chunk.range(of: "<\(tag)>"), let close = chunk.range(of: "</\(tag)>"),
              open.upperBound <= close.lowerBound else { return nil }
        return String(chunk[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func attribute(_ name: String, in chunk: Substring) -> Double? {
        guard let open = chunk.range(of: "\(name)=\""),
              let close = chunk[open.upperBound...].firstIndex(of: "\"") else { return nil }
        return Double(chunk[open.upperBound..<close])
    }

    /// `<gpxtpx:hr>83</gpxtpx:hr>`, `<ns3:hr>83</ns3:hr>` or `<hr>83</hr>`: a tag named `hr` with
    /// any prefix, and nothing else, so another tag that merely ends in "hr" isn't mistaken for it.
    private static let heartRatePattern = try! NSRegularExpression(pattern: #"<(?:[A-Za-z0-9_]+:)?hr>\s*([0-9]+(?:\.[0-9]+)?)\s*</"#)

    private static func heartRate(in chunk: Substring) -> Double? {
        let text = String(chunk)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = heartRatePattern.firstMatch(in: text, range: range),
              let number = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[number])
    }
}
