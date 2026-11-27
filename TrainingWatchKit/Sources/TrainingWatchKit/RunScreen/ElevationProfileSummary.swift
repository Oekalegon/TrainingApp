import Foundation

/// What VoiceOver says for the elevation profile (WATCH-149): the colour of the line says how steep the ground is, so
/// the words say it too, with the net change and the altitude now.
enum ElevationProfileSummary {
    /// A stretch is called level under this grade (percent), and the steepest stretch is worth saying from this.
    static let levelGrade = 2.0
    static let notableGrade = 3.0

    /// "12 metres higher than the start of the graph, now 47 metres, 6 percent uphill now, steepest stretch 14 percent
    /// uphill", or "no altitude yet".
    ///
    /// - Parameters:
    ///   - points: The profile as drawn.
    ///   - grades: The grade at each point (`ElevationGrade.grades(of:)`), computed once by the caller.
    static func spoken(_ points: [ElevationPoint], grades: [Double]) -> String {
        guard let first = points.first, let last = points.last, points.count >= 2, grades.count == points.count else {
            return "no altitude yet"
        }
        let change = Int((last.altitude - first.altitude).rounded())
        let direction = change == 0 ? "no change in altitude" : "\(abs(change)) metres " + (change > 0 ? "higher" : "lower") + " than the start of the graph"
        var parts = ["\(direction), now \(Int(last.altitude.rounded())) metres"]
        if let current = grades.last { parts.append(currentText(current)) }
        if let steepest = grades.max(by: { abs($0) < abs($1) }), abs(steepest) >= notableGrade {
            parts.append("steepest stretch \(Int(abs(steepest).rounded())) percent " + (steepest > 0 ? "uphill" : "downhill"))
        }
        return parts.joined(separator: ", ")
    }

    private static func currentText(_ grade: Double) -> String {
        let percent = Int(abs(grade).rounded())
        return abs(grade) < levelGrade ? "level now" : "\(percent) percent " + (grade > 0 ? "uphill" : "downhill") + " now"
    }
}
