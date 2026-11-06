import SwiftUI
import TrainingCore

/// The sheet that lists every workout for a day, best fit first (MVP5-156), opened from the planned-workout sheet's
/// "Find the Best Workout" (adding) and "Replace Workout" (editing). A search bar narrows the list by name; each row shows
/// the workout's size, what it does to the plan (the form at the end of the micro-cycle and the micro-cycle's planned time) and,
/// in orange, why it ranks lower. Every workout can be picked, also one with reasons against it.
///
/// The ranking runs when the sheet appears and stops when it closes. Ranking everything can take a while, so the sheet
/// says so while it works. Driven by ``WorkoutSuggestionsViewModel``.
struct WorkoutSuggestionsView: View {
    @Bindable var viewModel: WorkoutSuggestionsViewModel
    /// Called with the workout the athlete picked, just before the sheet closes.
    let onPick: (RankedWorkout) -> Void
    @Environment(\.dismiss) private var dismiss

    private var dayText: String {
        viewModel.day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    var body: some View {
        NavigationStack {
            List {
                switch viewModel.phase {
                case .idle, .ranking:
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(viewModel.rankingMessage)
                        }
                        .accessibilityElement(children: .combine)
                    }
                case .failed(let message):
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.red)
                    }
                case .ranked:
                    let rows = viewModel.filteredRows
                    if rows.isEmpty {
                        ContentUnavailableView(
                            viewModel.searchText.isEmpty ? "No Workouts" : "No Matches",
                            systemImage: "magnifyingglass",
                            description: Text(viewModel.searchText.isEmpty
                                ? "No workout in your library can be filled in for this day."
                                : "No workout is called \"\(viewModel.searchText)\".")
                        )
                    } else {
                        Section {
                            ForEach(rows) { row in
                                Button {
                                    onPick(row.ranked)
                                    dismiss()
                                } label: { RowContent(row: row) }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text(viewModel.searchText.isEmpty ? "Best Fit First" : "Matches")
                        } footer: {
                            Text("A workout that doesn't suit the plan is listed lower, with the reason, and can still be picked.")
                        }
                    }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search workouts")
            .navigationTitle(viewModel.replacedName.map { "Replace \($0)" } ?? "Choose a Workout")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationSubtitle(dayText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
            }
            .task { await viewModel.load() }
        }
    }
}

/// One workout: its name and size, what it does to the plan and the reasons against it.
private struct RowContent: View {
    let row: WorkoutSuggestionsViewModel.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.title).font(.headline)
            Text(row.detail).font(.subheadline).foregroundStyle(.secondary)
            ForEach(row.effects, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
            ForEach(row.reasons, id: \.self) {
                Label($0, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
