import Charts
import SwiftUI
import TrainingCore

/// The race markers every date-based chart draws (MVP2-104): a solid vertical rule at each race's
/// day with its outlined A/B/C circle at the top of the plot.
///
/// Drawn in a `chartOverlay` rather than as chart marks, so the rule can stop where the circle
/// begins instead of running through its letter. A race outside the plot's x-range is skipped
/// (the detail charts clip what they've loaded beyond the visible window), and a circle at the
/// plot's first or last day is kept inside it rather than half clipped.
///
/// Callers pass races with at most one per day (`WeekViewModel.chartRaces(in:)`), so circles never
/// stack.
struct RaceChartMarkers: View {
    let races: [Race]
    let proxy: ChartProxy
    let plotArea: CGRect
    /// Added to each race's date before positioning: half a day for the bar charts, whose
    /// `unit: .day` bars span the day after their x-value, so the rule sits in the middle of the
    /// race day's bar; zero for the line charts, whose points sit at the start of the day.
    var dayOffset: TimeInterval = 0

    /// Size of a race's circle; its rule starts just below it.
    static let markerSize: CGFloat = 22
    /// Half a day, for the bar charts' `dayOffset`.
    static let halfDay: TimeInterval = 12 * 60 * 60

    var body: some View {
        ForEach(races) { race in
            if let x = proxy.position(forX: race.date.addingTimeInterval(dayOffset)),
               x >= 0, x <= plotArea.width {
                marker(for: race, x: x)
            }
        }
    }

    @ViewBuilder
    private func marker(for race: Race, x: CGFloat) -> some View {
        let size = Self.markerSize
        let centerX = min(max(plotArea.minX + x, plotArea.minX + size / 2), plotArea.maxX - size / 2)
        Path { path in
            path.move(to: CGPoint(x: plotArea.minX + x, y: plotArea.minY + size))
            path.addLine(to: CGPoint(x: plotArea.minX + x, y: plotArea.maxY))
        }
        .stroke(Color.primary.opacity(0.6), lineWidth: 1.5)
        Image(systemName: race.priority.outlineMarkerSymbolName)
            .font(.system(size: size - 4))
            .foregroundStyle(Color.primary)
            .frame(width: size, height: size)
            .position(x: centerX, y: plotArea.minY + size / 2)
            .accessibilityLabel("\(race.priority.displayName) race, \(race.name)")
    }
}
