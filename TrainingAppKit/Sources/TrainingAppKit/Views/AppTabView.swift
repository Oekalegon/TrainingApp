import SwiftUI
import TrainingCore

/// The app's top-level screen (design doc §2.0): a bottom tab bar switching between the week view
/// ("Week") and the read-only athlete account screen ("Athlete") — replacing the week view's
/// former "Athlete" toolbar button + sheet.
///
/// Owns the single `WeekViewModel` for the app's lifetime so both tabs share it: `WeekView` reads
/// it directly, and `AthleteView` reads it via `WeekViewModel.athleteViewModel` — that coupling is
/// why `WeekViewModel` is constructed once here rather than inside `WeekView` itself.
public struct AppTabView: View {
    @State private var viewModel: WeekViewModel

    public init(model: TrainingModel, refresher: any ActivityRefreshing) {
        _viewModel = State(initialValue: WeekViewModel(model: model, refresher: refresher))
    }

    public var body: some View {
        TabView {
            WeekView(viewModel: viewModel)
                .tabItem {
                    Label("Week", systemImage: "calendar")
                }

            AthleteView(
                viewModel: viewModel.athleteViewModel,
                isResyncing: viewModel.isResyncing,
                onResync: { Task { await viewModel.resyncActivities() } },
                isDeduplicating: viewModel.isDeduplicating,
                onDeduplicate: { Task { await viewModel.deduplicateActivities() } }
            )
            .tabItem {
                Label("Athlete", systemImage: "person.circle")
            }
        }
    }
}
