import SwiftUI

/// One of the four fitness metrics shown throughout the week view — as an icon+value pill beside
/// each weekday row (`DayActivitiesSection`, MVP1-40), as an icon+name legend entry above the
/// chart (`FitnessChartView`), and as the metrics detail view's own subject (`MetricDetailView`,
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

    /// The underlying sports-science term's own abbreviation — shown alongside `name` in the
    /// metrics detail view (MVP1-45), since that's the term this app's day-to-day numbers actually
    /// come from (a search for "TRIMP"/"CTL"/"ATL"/"TSB" should land here, not just "Load").
    var abbreviation: String {
        switch self {
        case .load: "TRIMP"
        case .fitness: "CTL"
        case .fatigue: "ATL"
        case .form: "TSB"
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

    /// Plain-language explanation for the metrics detail view (MVP1-45) — what the number actually
    /// measures and, for the three trend metrics, the rolling window/formula behind it (TrainingKit
    /// design doc §5: CTL is a 42-day EWMA of Load, ATL a 7-day EWMA, TSB the day-before difference
    /// between them), so the numbers on screen aren't a mystery. Doesn't repeat `abbreviation`
    /// inline (e.g. spelling out "Chronic Training Load" for CTL) -- the view's header already
    /// shows `name` and `abbreviation` side by side, so restating the full term here would just be
    /// the same information twice in the same section.
    var explanation: String {
        switch self {
        case .load:
            return """
                Training Impulse for a single day, computed from your heart-rate data using a \
                Banister-style formula. At each heart rate, your heart rate reserve (how far \
                above resting your heart rate is, as a fraction of your full resting-to-maximum heart rate \
                range) gets weighted more heavily the higher it climbs, then multiplied by how \
                long you spend there. Load is the sum of that across the whole session, so both \
                duration and intensity count, but because the weighting grows exponentially, time \
                spent near your maximum heart rate adds far more than the same duration at an \
                easy, recovery pace.
                """
        case .fitness:
            return """
                A slow, 42-day rolling average of Load. It builds gradually with consistent \
                training and fades just as gradually when training drops off, tracking your \
                underlying aerobic fitness.
                """
        case .fatigue:
            return """
                A fast, 7-day rolling average of Load. It rises quickly after a hard week and \
                falls quickly once you ease off, tracking how tired your recent training has left \
                you.
                """
        case .form:
            return """
                Yesterday's Fitness minus yesterday's Fatigue. Positive means you're fresher than \
                your fitness would suggest — good timing for a big effort. Negative means fatigue \
                currently outweighs fitness — normal during a hard training block, but worth \
                watching if it stays low for a long time.
                """
        }
    }
}
