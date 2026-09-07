import SwiftUI
import TrainingCore

/// The app's single top-level screen (design doc §2.1): a 3-week CTL/ATL/TSB chart centered on
/// the displayed week, that week's activities/plans below it, swipe-to-navigate between weeks,
/// a "Today" toolbar button, and pull-to-refresh import.
public struct WeekView: View {
    @State private var viewModel: WeekViewModel

    private static let swipeThreshold: CGFloat = 60

    public init(model: TrainingModel, refresher: any ActivityRefreshing) {
        _viewModel = State(initialValue: WeekViewModel(model: model, refresher: refresher))
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.hasNoActivities {
                    EmptyStateView(isConnecting: viewModel.isRefreshing) {
                        Task { await viewModel.connectHealthData() }
                    }
                } else {
                    weekContent
                }
            }
            .navigationTitle(weekTitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Today", systemImage: "calendar") {
                        viewModel.goToToday()
                    }
                }
            }
            .task(id: viewModel.displayedWeekStart) {
                await viewModel.load()
            }
        }
    }

    private var weekContent: some View {
        List {
            Section {
                FitnessChartView(metrics: viewModel.chartMetrics)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            ForEach(viewModel.weekDates, id: \.self) { day in
                DayActivitiesSection(
                    day: day,
                    activities: viewModel.activities(on: day),
                    plans: viewModel.plans(on: day),
                    workoutName: { viewModel.workout(for: $0)?.name },
                    timeZone: viewModel.athleteTimeZone
                )
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .refreshable {
            await viewModel.refresh()
        }
        // `.simultaneousGesture`, not `.gesture`/`.highPriorityGesture` — either of those would
        // claim the touch ahead of List's own scroll recognizer and break vertical scrolling.
        // Running alongside it and only acting in `onEnded` when the horizontal component clearly
        // dominates keeps both usable, at the cost of an occasional false negative on a fast
        // diagonal swipe — acceptable for MVP 1.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in handleSwipeEnd(value) }
        )
    }

    private func handleSwipeEnd(_ value: DragGesture.Value) {
        guard abs(value.translation.width) > abs(value.translation.height) else { return }
        if value.translation.width < -Self.swipeThreshold {
            viewModel.goToNextWeek()
        } else if value.translation.width > Self.swipeThreshold {
            viewModel.goToPreviousWeek()
        }
    }

    private var weekTitle: String {
        let end = viewModel.weekDates.last ?? viewModel.displayedWeekStart
        var format = Date.FormatStyle.dateTime.day().month(.abbreviated)
        format.timeZone = viewModel.athleteTimeZone
        return "\(viewModel.displayedWeekStart.formatted(format)) – \(end.formatted(format))"
    }
}
