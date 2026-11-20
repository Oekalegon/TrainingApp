import Foundation
import Testing
@testable import TrainingWatchKit

@Suite("GPXTrack (WATCH-101)")
struct GPXTrackTests {
    private func gpx(_ points: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"><trk><trkseg>\(points)</trkseg></trk></gpx>
        """
    }

    private func point(lat: String = "45.1", lon: String = "6.9", time: String? = "2025-07-27T07:51:32Z",
                       ele: String? = "2124.6", extensions: String = "") -> String {
        "<trkpt lat=\"\(lat)\" lon=\"\(lon)\">"
            + (ele.map { "<ele>\($0)</ele>" } ?? "")
            + (time.map { "<time>\($0)</time>" } ?? "")
            + (extensions.isEmpty ? "" : "<extensions>\(extensions)</extensions>")
            + "</trkpt>"
    }

    @Test("reads position, time and altitude")
    func basics() throws {
        let points = GPXTrack.points(in: gpx(point()))
        let first = try #require(points.first)
        #expect(points.count == 1)
        #expect(first.latitude == 45.1)
        #expect(first.longitude == 6.9)
        #expect(first.altitude == 2124.6)
        #expect(first.time == ISO8601DateFormatter().date(from: "2025-07-27T07:51:32Z"))
        #expect(first.heartRate == nil)
    }

    @Test("reads Garmin's heart rate under any prefix, and a plain hr tag")
    func heartRatePrefixes() {
        let text = gpx(
            point(extensions: "<gpxtpx:TrackPointExtension><gpxtpx:hr>83</gpxtpx:hr><gpxtpx:cad>54</gpxtpx:cad></gpxtpx:TrackPointExtension>")
            + point(extensions: "<ns3:TrackPointExtension><ns3:hr>101</ns3:hr></ns3:TrackPointExtension>")
            + point(extensions: "<hr>120</hr>")
            + point(extensions: "<gpxtpx:hr> 130.0 </gpxtpx:hr>"))
        #expect(GPXTrack.points(in: text).map(\.heartRate) == [83, 101, 120, 130])
    }

    @Test("a point with no heart rate has none, and other tags ending in hr aren't mistaken for it")
    func noHeartRate() {
        let text = gpx(
            point(extensions: "<power>104</power>")
            + point(extensions: "<gpxtpx:cad>54</gpxtpx:cad><gpxtpx:chr>77</gpxtpx:chr>")
            + point(extensions: "<gpxtpx:hr>not a number</gpxtpx:hr>"))
        #expect(GPXTrack.points(in: text).map(\.heartRate) == [nil, nil, nil])
    }

    @Test("each point gets its own heart rate, not a neighbour's")
    func perPoint() {
        let text = gpx(
            point(extensions: "<gpxtpx:hr>83</gpxtpx:hr>")
            + point(time: "2025-07-27T07:51:33Z")
            + point(time: "2025-07-27T07:51:34Z", extensions: "<gpxtpx:hr>85</gpxtpx:hr>"))
        #expect(GPXTrack.points(in: text).map(\.heartRate) == [83, nil, 85])
    }

    @Test("points missing a position or a time are skipped")
    func skipsIncomplete() {
        let text = gpx(
            point() + point(time: nil) + point(lat: "x") + "<trkpt lon=\"6.9\"><time>2025-07-27T07:51:32Z</time></trkpt>"
            + point(time: "2025-07-27T07:51:40Z"))
        #expect(GPXTrack.points(in: text).count == 2)
    }

    @Test("a missing altitude is 0, and times with fractional seconds are read")
    func altitudeAndFractionalSeconds() throws {
        let points = GPXTrack.points(in: gpx(point(time: "2025-07-27T07:51:32.500Z", ele: nil)))
        let first = try #require(points.first)
        #expect(first.altitude == 0)
        let base = try #require(ISO8601DateFormatter().date(from: "2025-07-27T07:51:32Z"))
        #expect(abs(first.time.timeIntervalSince(base) - 0.5) < 0.001)
    }

    @Test("text with no track points, or not GPX at all, gives none")
    func nothing() {
        #expect(GPXTrack.points(in: gpx("")).isEmpty)
        #expect(GPXTrack.points(in: "").isEmpty)
        #expect(GPXTrack.points(in: "not xml").isEmpty)
    }

    @Test("points keep their order")
    func order() {
        let times = ["2025-07-27T07:51:32Z", "2025-07-27T07:51:33Z", "2025-07-27T07:51:34Z"]
        let points = GPXTrack.points(in: gpx(times.map { point(time: $0) }.joined()))
        #expect(points.map(\.time) == times.compactMap { ISO8601DateFormatter().date(from: $0) })
    }
}
