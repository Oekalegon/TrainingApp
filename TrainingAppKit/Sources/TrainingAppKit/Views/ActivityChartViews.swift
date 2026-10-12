import Charts
import SwiftUI
import TrainingCore

/// The activity detail's heart-rate chart (MVP2-146): heart rate against time since the activity
/// began, over a coloured band for each step the Watch recorded, with a thin line where each step
/// started, so the plan's steps can be read straight off the curve.
struct ActivityHeartRateChart: View {
    let data: ActivityChartData

    var body: some View {
        Chart {
            ActivityStepMarks(steps: data.steps)
            ForEach(Array(data.heartRate.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time", point.elapsed), y: .value("Heart rate", point.value),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(.red)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
        .chartXScale(domain: 0...max(data.duration, 1))
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis { activityTimeAxis(duration: data.duration) }
        // On the left like the pace chart's, so the two plots line up and a step's band is at the same
        // x in both.
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 160)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate over time")
        .accessibilityValue(Self.spokenSummary(of: data))
    }

    /// "From 113 to 171 beats per minute, 14 steps marked."
    static func spokenSummary(of data: ActivityChartData) -> String {
        let values = data.heartRate.map(\.value)
        guard let low = values.min(), let high = values.max() else { return "No heart rate recorded" }
        var text = "From \(Int(low.rounded())) to \(Int(high.rounded())) beats per minute"
        if !data.steps.isEmpty { text += ", \(data.steps.count) steps marked" }
        return text
    }
}

/// The activity detail's pace chart (MVP2-146): pace against time, fastest at the top like the
/// speed it comes from, over the same step bands as the heart-rate chart so the two line up.
struct ActivityPaceChart: View {
    let data: ActivityChartData
    let distanceSystem: DistanceSystem

    var body: some View {
        // Pace is plotted negated so that faster (a smaller number) is higher; the axis labels undo it.
        let domain = data.paceDomain ?? 0...1
        return Chart {
            ActivityStepMarks(steps: data.steps)
            ForEach(Array(data.pace.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time", point.elapsed), y: .value("Pace", -point.value),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
        .chartXScale(domain: 0...max(data.duration, 1))
        .chartYScale(domain: -domain.upperBound...(-domain.lowerBound))
        .chartXAxis { activityTimeAxis(duration: data.duration) }
        .chartYAxis {
            // Negated like the data: round pace values (every 30 s, say), and the plot's own range.
            let ticks = ActivityChartData.niceTicks(in: domain, steps: ActivityChartData.paceTickSteps).map { -$0 }
            AxisMarks(position: .leading, values: ticks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let negated = value.as(Double.self) {
                        Text(Self.axisText(secondsPerKilometer: -negated, in: distanceSystem))
                    }
                }
            }
        }
        .frame(height: 160)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pace over time")
        .accessibilityValue(Self.spokenSummary(of: data, in: distanceSystem))
    }

    /// "6:32", the pace on the axis; the unit is in the section's caption.
    static func axisText(secondsPerKilometer: Double, in system: DistanceSystem) -> String {
        WorkoutBlockCard.paceText(secondsPerKilometer: secondsPerKilometer, in: system)
            .replacingOccurrences(of: " /km", with: "").replacingOccurrences(of: " /mi", with: "")
    }

    /// "From 5:30 to 7:10 per kilometer, 14 steps marked."
    static func spokenSummary(of data: ActivityChartData, in system: DistanceSystem) -> String {
        let values = data.pace.map(\.value)
        guard let fast = values.min(), let slow = values.max() else { return "No pace recorded" }
        let unit = system == .metric ? "per kilometer" : "per mile"
        var text = "From \(axisText(secondsPerKilometer: fast, in: system)) to \(axisText(secondsPerKilometer: slow, in: system)) \(unit)"
        if !data.steps.isEmpty { text += ", \(data.steps.count) steps marked" }
        return text
    }
}

/// The step bands and start lines both charts share.
struct ActivityStepMarks: ChartContent {
    let steps: [ActivityChartData.StepSpan]

    var body: some ChartContent {
        ForEach(steps) { span in
            RectangleMark(xStart: .value("Step start", span.start), xEnd: .value("Step end", span.end))
                .foregroundStyle(span.kind.chartColor(index: span.id).opacity(span.kind == nil ? 0.12 : 0.18))
        }
        ForEach(steps) { span in
            RuleMark(x: .value("Step start", span.start))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 0.5))
        }
    }
}

/// The time axis both charts share: elapsed time since the start, as m:ss or h:mm:ss, at round values.
@AxisContentBuilder
func activityTimeAxis(duration: TimeInterval) -> some AxisContent {
    AxisMarks(values: ActivityChartData.niceTicks(in: 0...max(duration, 1), steps: ActivityChartData.timeTickSteps)) { value in
        AxisGridLine()
        AxisValueLabel {
            if let seconds = value.as(Double.self) {
                Text(WorkoutBlockCard.durationText(seconds))
            }
        }
    }
}

/// What the coloured bands mean: one dot and name for each role the steps have.
struct ActivityStepLegend: View {
    let steps: [ActivityChartData.StepSpan]

    var body: some View {
        let kinds = Self.kinds(in: steps)
        HStack(spacing: 12) {
            if kinds.isEmpty {
                Text("Bands show the recorded steps.")
            } else {
                ForEach(kinds, id: \.self) { kind in
                    HStack(spacing: 4) {
                        Circle().fill(Optional(kind).chartColor(index: 0)).frame(width: 8, height: 8).accessibilityHidden(true)
                        Text(kind.displayName)
                    }
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    /// The roles present, in the order a workout has them.
    static func kinds(in steps: [ActivityChartData.StepSpan]) -> [StepKind] {
        [StepKind.warmup, .work, .recovery, .cooldown].filter { kind in steps.contains { $0.kind == kind } }
    }
}

extension Optional where Wrapped == StepKind {
    /// The band colour for a step's role: yellow for the warm-up, red for work, green for recovery and
    /// blue for the cool-down; a step with no known role alternates two greys so neighbours differ.
    func chartColor(index: Int) -> Color {
        switch self {
        case .warmup?: .yellow
        case .work?: .red
        case .recovery?: .green
        case .cooldown?: .blue
        case nil: index.isMultiple(of: 2) ? .gray : .secondary
        }
    }
}
