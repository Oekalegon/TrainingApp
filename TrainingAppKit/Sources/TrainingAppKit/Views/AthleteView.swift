import SwiftUI
import TrainingCore

/// The read-only athlete account screen (design doc §2.3): everything here is display-only — no
/// editing, no save button, no `heartRateZoneHistory` timeline, just what's currently in effect.
struct AthleteView: View {
    let viewModel: AthleteViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        AvatarView(initials: viewModel.initials)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    LabeledContent("Name", value: viewModel.displayName)
                    LabeledContent("Sex", value: viewModel.athlete.sex.displayName)
                }

                if let settings = viewModel.currentHeartRateZoneSettings {
                    Section("Heart Rate Zones") {
                        LabeledContent("Resting HR", value: "\(Int(settings.restingHeartRateBPM.rounded())) bpm")
                        LabeledContent("Max HR", value: "\(Int(settings.maxHeartRateBPM.rounded())) bpm")
                        if let lactateThreshold = settings.lactateThresholdHeartRateBPM {
                            LabeledContent("Lactate Threshold", value: "\(Int(lactateThreshold.rounded())) bpm")
                        }
                        LabeledContent("Method", value: settings.zoneMethod.displayName)
                    }
                } else {
                    Section("Heart Rate Zones") {
                        Text("No heart-rate zone settings on record yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Pace") {
                    LabeledContent("Threshold Pace", value: viewModel.thresholdPaceText)
                }

                Section("Calendar") {
                    LabeledContent("Week Starts On", value: viewModel.athlete.weekStartsOn.displayName)
                    LabeledContent("Time Zone", value: viewModel.athlete.timeZone.identifier)
                }
            }
            .navigationTitle("Athlete")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct AvatarView: View {
    let initials: String

    var body: some View {
        Text(initials)
            .font(.title.bold())
            .foregroundStyle(.white)
            .frame(width: 72, height: 72)
            .background(Circle().fill(.blue))
    }
}
