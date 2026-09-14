import SwiftUI

/// One of the four fitness metrics shown throughout the week view — as an icon+value pill beside
/// each weekday row (`DayActivitiesSection`, MVP1-40), as an icon+name legend entry above the
/// chart (`FitnessChartView`), and as an entry in the metrics info sheet (`FitnessMetricsInfoView`,
/// MVP1-45). All three key off this single mapping, so the icon, its accessibility name, and (for
/// the chart) its color can't drift between them.
enum TrainingMetricKind: CaseIterable {
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

    /// Plain-language explanation for the metrics info sheet (MVP1-45) — what the number actually
    /// measures and, for the three trend metrics, the rolling window/formula behind it (TrainingKit
    /// design doc §5: CTL is a 42-day EWMA of Load, ATL a 7-day EWMA, TSB the day-before difference
    /// between them), so the numbers on screen aren't a mystery.
    var explanation: String {
        switch self {
        case .load:
            return "Training load for a single day, computed from your heart-rate data using a "
                + "Banister-style TRIMP formula. Duration and intensity both count, so a short hard "
                + "session and a long easy one can land on a similar number."
        case .fitness:
            return "Your Chronic Training Load (CTL) — a slow, 42-day rolling average of Load. It "
                + "builds gradually with consistent training and fades just as gradually when "
                + "training drops off, tracking your underlying aerobic fitness."
        case .fatigue:
            return "Your Acute Training Load (ATL) — a fast, 7-day rolling average of Load. It rises "
                + "quickly after a hard week and falls quickly once you ease off, tracking how tired "
                + "your recent training has left you."
        case .form:
            return "Training Stress Balance (TSB): yesterday's Fitness minus yesterday's Fatigue. "
                + "Positive means you're fresher than your fitness would suggest — good timing for a "
                + "big effort. Negative means fatigue currently outweighs fitness — normal during a "
                + "hard training block, but worth watching if it stays low for a long time."
        }
    }
}
