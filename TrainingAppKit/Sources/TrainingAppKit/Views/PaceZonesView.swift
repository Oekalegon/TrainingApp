import SwiftUI
import TrainingCore

/// Pace Zones (MVP2-123, MVP2-132, design doc §2.3): the threshold pace in effect and the history of
/// paces with the date each took effect. The athlete adds a pace from a date with the toolbar button
/// (or taps a history row to change that entry), and swipes a row to delete it. The zones themselves
/// aren't built yet (MVP8), so the screen says so rather than leaving a gap.
struct PaceZonesView: View {
    let viewModel: AthleteViewModel
    let weekViewModel: WeekViewModel
    @State private var editing: PaceDraft?
    @State private var isShowingError = false

    var body: some View {
        List {
            Section {
                LabeledContent("Threshold Pace", value: viewModel.thresholdPaceText)
            } footer: {
                Text("Pace zones aren't available yet.")
            }

            Section("History") {
                ForEach(viewModel.paceHistory, id: \.effectiveDate) { entry in
                    Button {
                        editing = PaceDraft(
                            prefilling: entry.paceModel, effectiveDate: AthleteViewModel.editingDate(for: entry.effectiveDate)
                        )
                    } label: {
                        LabeledContent {
                            Text(AthleteViewModel.paceText(entry.paceModel.thresholdPaceSecondsPerKilometer))
                        } label: {
                            Text(dateText(entry.effectiveDate))
                        }
                    }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        if viewModel.paceHistory.count > 1 {
                            Button("Delete", role: .destructive) {
                                Task {
                                    if await !weekViewModel.removePaceSettings(on: entry.effectiveDate) { isShowingError = true }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(AthleteRoute.paceZones.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Pace", systemImage: "plus") {
                    editing = PaceDraft(prefilling: viewModel.athlete.paceModel, effectiveDate: .now)
                }
            }
        }
        .sheet(item: Binding(
            get: { editing.map(EditingDraft.init) },
            set: { editing = $0?.draft }
        )) { item in
            ThresholdPaceSheet(draft: item.draft) { draft in
                await weekViewModel.recordThresholdPace(
                    secondsPerKilometer: draft.thresholdPaceSecondsPerKilometer, from: draft.effectiveDate
                )
            }
        }
        .alert("Couldn't Save", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The change couldn't be saved. Try again.")
        }
    }

    private func dateText(_ date: Date) -> String {
        if date == .distantPast { return "Since the start" }
        return date.formatted(Date.FormatStyle(timeZone: viewModel.athlete.timeZone).day().month(.abbreviated).year())
    }

    /// Wraps a draft for `.sheet(item:)`, which needs an `Identifiable` item.
    private struct EditingDraft: Identifiable {
        let draft: PaceDraft
        var id: Date { draft.effectiveDate }
    }
}
