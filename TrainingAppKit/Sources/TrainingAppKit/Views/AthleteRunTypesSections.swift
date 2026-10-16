import SwiftUI
import TrainingCore

/// The athlete's run types per micro day, below Running Availability on the Calendar screen (MVP5-112): a micro
/// length (7, 10 or 14 days) and the ``RunTypePickerSections`` for it. Changes are saved at once in an
/// ``AthleteRunTypesStore``. Weekday names start from the athlete's week start. Meant to sit inside a `List`.
struct AthleteRunTypesSections: View {
    @State private var viewModel: RunTypePickerViewModel
    private let store: AthleteRunTypesStore

    init(weekStart: Weekday, store: AthleteRunTypesStore = AthleteRunTypesStore()) {
        self.store = store
        let saved = store.load()
        _viewModel = State(initialValue: RunTypePickerViewModel(
            preferences: saved.preferences, microLength: saved.microLength, firstWeekday: weekStart))
    }

    var body: some View {
        Section {
            Picker("Micro-cycle length", selection: Binding(
                get: { viewModel.microLength }, set: { viewModel.setMicroLength($0) }
            )) {
                ForEach(RunTypePickerViewModel.supportedMicroLengths, id: \.self) { Text("\($0) days").tag($0) }
            }
        } footer: {
            Text("The run types follow the micro-cycle of a plan, which lasts 7, 10 or 14 days. Weekdays are shown from your week start.")
        }
        RunTypePickerSections(viewModel: viewModel)
            .onChange(of: viewModel.draft) { save() }
            .onChange(of: viewModel.microLength) { save() }
    }

    private func save() { store.save(viewModel.draft, microLength: viewModel.microLength) }
}
