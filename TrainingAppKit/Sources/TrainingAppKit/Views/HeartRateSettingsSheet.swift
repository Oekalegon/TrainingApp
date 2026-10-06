import SwiftUI
import TrainingCore

/// The sheet for recording heart-rate settings from a date (MVP2-132, design doc §2.3): the date they
/// take effect, resting and maximum heart rate, an optional lactate threshold and the zone method.
/// Saving on a day that already has an entry replaces it. While the resting heart rate follows Apple
/// Health, it's shown but can't be edited here.
struct HeartRateSettingsSheet: View {
    @State var draft: HeartRateSettingsDraft
    /// Whether the resting heart rate comes from Apple Health and so isn't editable.
    let isRestingLocked: Bool
    /// Saves the settings; returns whether it worked. The sheet closes only when it did.
    let onSave: (HeartRateSettingsDraft) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var isShowingSaveError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Effective From", selection: $draft.effectiveDate, displayedComponents: .date)
                } footer: {
                    Text("Activities from this day on are scored with these settings; earlier ones keep theirs.")
                }

                Section {
                    if isRestingLocked {
                        LabeledContent("Resting Heart Rate", value: "\(draft.restingHeartRate) bpm")
                    } else {
                        Stepper("Resting Heart Rate: \(draft.restingHeartRate) bpm", value: $draft.restingHeartRate, in: 25...120)
                    }
                    Stepper("Maximum Heart Rate: \(draft.maxHeartRate) bpm", value: $draft.maxHeartRate, in: 100...230)
                    Toggle("Lactate Threshold", isOn: Binding(
                        get: { draft.lactateThresholdHeartRate != nil },
                        set: { draft.lactateThresholdHeartRate = $0 ? min(draft.maxHeartRate - 10, 170) : nil }
                    ))
                    if let threshold = draft.lactateThresholdHeartRate {
                        Stepper(
                            "Lactate Threshold: \(threshold) bpm",
                            value: Binding(get: { threshold }, set: { draft.lactateThresholdHeartRate = $0 }),
                            in: 60...230
                        )
                    }
                    Picker("Zone Method", selection: $draft.zoneMethod) {
                        ForEach(HeartRateSettingsSheet.methods, id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                } footer: {
                    if isRestingLocked {
                        Text("Your resting heart rate comes from Apple Health. Turn that off on the previous screen to enter your own.")
                    } else if let message = draft.validationMessage {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Heart Rate Settings")
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
                Text("The heart-rate settings couldn't be saved. Try again.")
            }
        }
    }

    /// The zone methods to choose from, in the order the picker lists them.
    static let methods: [HeartRateZoneMethod] = [.karvonen, .percentageOfMaxHeartRate, .lactateThreshold]
}
