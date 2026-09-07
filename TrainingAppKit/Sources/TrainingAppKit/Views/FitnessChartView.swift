import Charts
import SwiftUI
import TrainingCore

/// The 3-week CTL/ATL/TSB trend chart at the top of the week view (design doc §2.1).
struct FitnessChartView: View {
    let metrics: [FitnessMetrics]

    var body: some View {
        Chart(metrics, id: \.day) { point in
            LineMark(x: .value("Day", point.day), y: .value("CTL", point.ctl))
                .foregroundStyle(by: .value("Series", "Fitness (CTL)"))
            LineMark(x: .value("Day", point.day), y: .value("ATL", point.atl))
                .foregroundStyle(by: .value("Series", "Fatigue (ATL)"))
            LineMark(x: .value("Day", point.day), y: .value("TSB", point.tsb))
                .foregroundStyle(by: .value("Series", "Form (TSB)"))
        }
        .chartForegroundStyleScale([
            "Fitness (CTL)": Color.blue,
            "Fatigue (ATL)": Color.orange,
            "Form (TSB)": Color.green,
        ])
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 180)
        .padding(.horizontal)
    }
}
