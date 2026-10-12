import Charts
import SwiftUI
import TrainingCore

/// The activity detail's heart-rate chart (MVP2-146): heart rate against time since the activity
/// began, over a coloured band for each step the Watch recorded, with a thin line where each step
/// started, so the plan's steps can be read straight off the curve.
struct ActivityHeartRateChart: View {
    let data: ActivityChartData
    /// The step to emphasise (MVP2-146); the others fade.
    var highlightedStepID: Int? = nil

    var body: some View {
        Chart {
            ActivityStepMarks(steps: data.steps, highlightedID: highlightedStepID)
            ForEach(Array(data.heartRate.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time", point.elapsed), y: .value("Heart rate", point.value),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(.red)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            activityLonePoints(data.heartRate, color: .red)
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
        .accessibilityValue(Self.spokenSummary(of: data, highlightedStepID: highlightedStepID))
    }

    /// "From 113 to 171 beats per minute, 14 steps marked, step 3 highlighted."
    static func spokenSummary(of data: ActivityChartData, highlightedStepID: Int? = nil) -> String {
        let values = data.heartRate.map(\.value)
        guard let low = values.min(), let high = values.max() else { return "No heart rate recorded" }
        var text = "From \(Int(low.rounded())) to \(Int(high.rounded())) beats per minute"
        if data.planStepCount > 0 { text += ", \(data.planStepCount) steps marked" }
        text += highlightText(highlightedStepID, in: data)
        return text
    }

    /// ", step 3 highlighted", for a highlighted step that is on the chart; nothing otherwise.
    static func highlightText(_ highlightedStepID: Int?, in data: ActivityChartData) -> String {
        guard let id = ActivityStepMarks.effectiveHighlight(highlightedStepID, in: data.steps) else { return "" }
        let isAfterPlan = data.steps.first { $0.id == id }?.isOutsidePlan == true
        return isAfterPlan ? ", the time after the plan highlighted" : ", step \(id + 1) highlighted"
    }
}

/// The activity detail's pace chart (MVP2-146): pace against time, fastest at the top like the
/// speed it comes from, over the same step bands as the heart-rate chart so the two line up.
struct ActivityPaceChart: View {
    let data: ActivityChartData
    let distanceSystem: DistanceSystem
    /// The step to emphasise (MVP2-146); the others fade.
    var highlightedStepID: Int? = nil

    var body: some View {
        // Pace is plotted negated so that faster (a smaller number) is higher; the axis labels undo it.
        let domain = data.paceDomain ?? 0...1
        return Chart {
            ActivityStepMarks(steps: data.steps, highlightedID: highlightedStepID)
            ForEach(Array(data.pace.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time", point.elapsed), y: .value("Pace", -point.value),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            activityLonePoints(data.pace, color: .blue, negated: true)
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
        .accessibilityValue(Self.spokenSummary(of: data, in: distanceSystem, highlightedStepID: highlightedStepID))
    }

    /// "6:32", the pace on the axis; the unit is in the section's caption.
    static func axisText(secondsPerKilometer: Double, in system: DistanceSystem) -> String {
        WorkoutBlockCard.paceText(secondsPerKilometer: secondsPerKilometer, in: system)
            .replacingOccurrences(of: " /km", with: "").replacingOccurrences(of: " /mi", with: "")
    }

    /// "From 5:30 to 7:10 per kilometer, 14 steps marked, step 3 highlighted."
    static func spokenSummary(of data: ActivityChartData, in system: DistanceSystem, highlightedStepID: Int? = nil) -> String {
        let values = data.pace.map(\.value)
        guard let fast = values.min(), let slow = values.max() else { return "No pace recorded" }
        let unit = system == .metric ? "per kilometer" : "per mile"
        var text = "From \(axisText(secondsPerKilometer: fast, in: system)) to \(axisText(secondsPerKilometer: slow, in: system)) \(unit)"
        if data.planStepCount > 0 { text += ", \(data.planStepCount) steps marked" }
        text += ActivityHeartRateChart.highlightText(highlightedStepID, in: data)
        return text
    }
}

/// A dot for each reading that is alone in its segment: a line needs two points, so without this a
/// lone reading between two gaps would draw nothing.
@ChartContentBuilder
func activityLonePoints(_ points: [ActivityChartData.Point], color: Color, negated: Bool = false) -> some ChartContent {
    let counts = Dictionary(points.map { ($0.segment, 1) }, uniquingKeysWith: +)
    let lone = points.filter { counts[$0.segment] == 1 }
    ForEach(lone, id: \.elapsed) { point in
        PointMark(x: .value("Time", point.elapsed), y: .value("Value", negated ? -point.value : point.value))
            .symbolSize(12)
            .foregroundStyle(color)
    }
}

/// The step bands and start lines both charts share. With a step highlighted (MVP2-146) its band is
/// strong and the others fade, and its start and end are drawn as solid lines.
struct ActivityStepMarks: ChartContent {
    let steps: [ActivityChartData.StepSpan]
    var highlightedID: Int? = nil

    /// How opaque a step's band is: its usual tint, or with a step highlighted, strong for that step and
    /// faint for the rest.
    static func bandOpacity(of span: ActivityChartData.StepSpan, highlightedID: Int?) -> Double {
        guard let highlightedID else { return span.kind == nil ? 0.12 : 0.18 }
        return span.id == highlightedID ? 0.5 : 0.06
    }

    /// The highlighted id if one of `steps` has it, else `nil`: a recorded step with no time on the
    /// axis (it was clipped away) has no band, and fading every band for a highlight that can't be
    /// seen would only look broken.
    static func effectiveHighlight(_ highlightedID: Int?, in steps: [ActivityChartData.StepSpan]) -> Int? {
        highlightedID.flatMap { id in steps.contains { $0.id == id } ? id : nil }
    }

    var body: some ChartContent {
        let highlight = Self.effectiveHighlight(highlightedID, in: steps)
        ForEach(steps) { span in
            RectangleMark(xStart: .value("Step start", span.start), xEnd: .value("Step end", span.end))
                // The time after the plan is plain grey: it isn't a step, so it has no role colour.
                .foregroundStyle((span.isOutsidePlan ? Color.gray : span.kind.chartColor(index: span.id)).opacity(Self.bandOpacity(of: span, highlightedID: highlight)))
        }
        ForEach(steps) { span in
            RuleMark(x: .value("Step start", span.start))
                .foregroundStyle(span.id == highlight ? Color.primary : Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: span.id == highlight ? 1.5 : 0.5))
        }
        ForEach(steps.filter { $0.id == highlight }) { span in
            RuleMark(x: .value("Step end", span.end))
                .foregroundStyle(Color.primary)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
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
        let hasAfterPlan = steps.contains { $0.isOutsidePlan }
        // A grid that wraps whole entries onto the next row, so five of them (every role and the time
        // after the plan) don't break a name across lines.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 4) {
            if kinds.isEmpty && !hasAfterPlan {
                Text("Bands show the recorded steps.")
            } else {
                ForEach(kinds, id: \.self) { kind in
                    HStack(spacing: 4) {
                        Circle().fill(Optional(kind).chartColor(index: 0)).frame(width: 8, height: 8).accessibilityHidden(true)
                        Text(kind.displayName).lineLimit(1)
                    }
                }
                if hasAfterPlan {
                    HStack(spacing: 4) {
                        Circle().fill(Color.gray).frame(width: 8, height: 8).accessibilityHidden(true)
                        Text("After the plan").lineLimit(1)
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
