import SwiftUI

/// One of the four fitness metrics shown throughout the week view — as an icon+value pill beside
/// each weekday row (`DayActivitiesSection`, MVP1-40) and as an icon+name legend entry above the
/// chart (`FitnessChartView`). Both places key off this single mapping, so the icon, its
/// accessibility name, and (for the chart) its color can't drift between the two.
enum TrainingMetricKind {
    case load, fitness, fatigue, form

    /// SF Symbol shown for this metric — a bolt for that day's raw training load, a full/quarter
    /// battery for the chronic/acute load trends (Fitness/Fatigue), and a half-swung gauge for
    /// Form's balance between them.
    var icon: String {
        switch self {
        case .load: "bolt.fill"
        case .fitness: "battery.100"
        case .fatigue: "battery.25"
        case .form: "gauge.with.dots.needle.50percent"
        }
    }

    /// Plain-language name — used as the chart legend's label and as the accessibility label for
    /// the day list's icon-only pills, so VoiceOver announces "Fitness, 42" rather than reading
    /// the icon's own SF Symbol name ("battery 100 percent").
    var name: String {
        switch self {
        case .load: "Load"
        case .fitness: "Fitness"
        case .fatigue: "Fatigue"
        case .form: "Form"
        }
    }

    /// Series color used by `FitnessChartView`'s trend lines and legend. The day list's pills
    /// deliberately don't use this — see `MetricPillView`'s doc comment.
    var color: Color {
        switch self {
        case .load: .red
        case .fitness: .blue
        case .fatigue: .orange
        case .form: .green
        }
    }
}
