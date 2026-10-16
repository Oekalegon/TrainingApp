import SwiftUI
import TrainingCore

/// A sheet for adding just a race (MVP5-125): what the Plans tab offers, since individual workouts are
/// not added from there. The week view's `AddEntrySheet` has the same race fields beside a planned
/// workout.
struct AddRaceSheet: View {
    let viewModel: RaceSheetViewModel
    @Environment(\.dismiss) private var dismiss
    /// The failure to show, copied when the save resolves because ``RaceSheetViewModel/saveError`` can't be cleared from here.
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form { RaceFormFields(viewModel: viewModel) }
                .navigationTitle("Add Race")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task {
                                if await viewModel.save() { dismiss() } else { failure = viewModel.saveError }
                            }
                        } label: { Image(systemName: "checkmark") }
                            .accessibilityLabel("Save")
                            .disabled(!viewModel.canSave || viewModel.isSaving)
                    }
                }
                .alert(
                    "Couldn't Save the Race",
                    isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
                    presenting: failure
                ) { _ in
                    Button("OK", role: .cancel) {}
                } message: { message in
                    Text(message)
                }
        }
    }
}
