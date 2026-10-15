import SwiftUI

/// The sheet for recording a threshold pace from a date (MVP2-132, design doc §2.3). Saving on a day
/// that already has an entry replaces it; the zone multipliers carry over from the pace in effect.
struct ThresholdPaceSheet: View {
    @State var draft: PaceDraft
    /// Saves the pace; returns whether it worked. The sheet closes only when it did.
    let onSave: (PaceDraft) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var isShowingSaveError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Effective From", selection: $draft.effectiveDate, displayedComponents: .date)
                } footer: {
                    Text("Plans use the latest pace you've entered.")
                }

                Section {
                    Stepper("Minutes: \(draft.minutes)", value: $draft.minutes, in: 2...20)
                    Stepper("Seconds: \(draft.seconds)", value: $draft.seconds, in: 0...59)
                    LabeledContent("Threshold Pace", value: String(format: "%d:%02d /km", draft.minutes, draft.seconds))
                } footer: {
                    if let message = draft.validationMessage {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Threshold Pace")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            let saved = await onSave(draft)
                            isSaving = false
                            if saved { dismiss() } else { isShowingSaveError = true }
                        }
                    }
                    .disabled(isSaving || draft.validationMessage != nil)
                }
            }
            .alert("Couldn't Save", isPresented: $isShowingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The threshold pace couldn't be saved. Try again.")
            }
        }
    }
}
