import Charts
import SwiftUI
import TrainingCore

/// The week view's graph panel "Time in zone" page (MVP1-55, design doc §2.1) — each day of the
/// displayed week's heart-rate time-in-zone breakdown, stacked by zone.
///
/// Deliberately scoped to just the displayed week, not the 3-week window `FitnessChartView`/
/// `DailyLoadChartView` share: unlike load/CTL/ATL/TSB (already computed for the whole
/// `chartRange` by `TrainingModel.recompute`), time-in-zone here is summed per activity on demand
/// (`WeekViewModel.timeInZoneByDay()`), and widening that to 21 days would triple the per-swipe-
/// frame cost its memoization is built to avoid.
struct TimeInZoneChartView: View {
    let days: [DayTimeInZone]

    /// Zone 0 ("below zone 1") is omitted, matching `ActivityDetailView`'s own convention — it's
    /// unclassified low-intensity time, not one of the athlete's actual training zones.
    private static let zones = 1...5

    /// A provisional cool-to-hot ramp, distinct from `TrainingMetricKind`'s own colors — heart-rate
    /// zone names/colors proper are still backlog (MVP1-54); this stands in until that ticket
    /// assigns real ones.
    private static func color(forZone zone: Int) -> Color {
        switch zone {
        case 1: .blue
        case 2: .green
        case 3: .yellow
        case 4: .orange
        default: .red
        }
    }

    /// One zone's bar for one day — flattened out of `days` × `zones` up front so the `Chart`
    /// builder below is a single flat `ForEach` rather than a nested one. The nested form (a
    /// `ForEach` of days, each containing a `ForEach` of zones building a `BarMark` from a
    /// dictionary lookup plus string interpolation) was slow enough for the type checker to give
    /// up entirely ("unable to type-check this expression in reasonable time").
    private struct ZoneBar: Identifiable {
        let day: Date
        let zone: Int
        let minutes: Double
        var id: String { "\(day.timeIntervalSince1970)-\(zone)" }
    }

    private var zoneBars: [ZoneBar] {
        days.flatMap { day in
            Self.zones.map { zone in
                ZoneBar(day: day.day, zone: zone, minutes: (day.timeInZone.seconds[zone] ?? 0) / 60)
            }
        }
    }

    private var hasAnyTime: Bool {
        days.contains { $0.timeInZone.total > 0 }
    }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if hasAnyTime {
                    chart
                } else {
                    ContentUnavailableView(
                        "No Heart-Rate Data",
                        systemImage: "heart.slash",
                        description: Text("No heart-rate zones recorded this week.")
                    )
                }
            }
            .frame(height: 140)
            .padding(.horizontal)

            legend
        }
    }

    private var chart: some View {
        Chart(zoneBars) { bar in
            BarMark(
                x: .value("Day", bar.day, unit: .day),
                y: .value("Minutes", bar.minutes)
            )
            .foregroundStyle(by: .value("Zone", "Zone \(bar.zone)"))
        }
        // A literal, not a `Dictionary` built from `Self.zones`: `.chartForegroundStyleScale`
        // takes a `KeyValuePairs`, which (unlike `Dictionary`) can only be constructed via literal
        // syntax, not from an existing collection.
        .chartForegroundStyleScale([
            "Zone 1": Self.color(forZone: 1),
            "Zone 2": Self.color(forZone: 2),
            "Zone 3": Self.color(forZone: 3),
            "Zone 4": Self.color(forZone: 4),
            "Zone 5": Self.color(forZone: 5),
        ])
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
            }
        }
        .chartLegend(.hidden)
    }

    private var legend: some View {
        HStack(spacing: 8) {
            ForEach(Self.zones, id: \.self) { zone in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Self.color(forZone: zone))
                        .frame(width: 8, height: 8)
                    Text("Z\(zone)")
                }
            }
        }
        .font(.caption2)
        .padding(.horizontal)
    }
}
