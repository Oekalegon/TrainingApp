import SwiftUI
import TrainingCore

/// The read-only athlete account screen (design doc §2.3): everything here is display-only — no
/// editing of the profile itself, no `heartRateZoneHistory` timeline, just what's currently in
/// effect. The one action this screen offers, "Force Full Resync", doesn't edit the profile — it
/// re-imports activities from scratch, for recovering from a mapping fix that already-imported
/// activities wouldn't otherwise pick up (design doc §2.3).
struct AthleteView: View {
    let viewModel: AthleteViewModel
    let isResyncing: Bool
    let onResync: () -> Void
    let isDeduplicating: Bool
    let onDeduplicate: () -> Void
    @State private var isConfirmingResync = false

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

                Section {
                    Button {
                        isConfirmingResync = true
                    } label: {
                        HStack {
                            Text("Force Full Resync")
                            if isResyncing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isResyncing || isDeduplicating)

                    Button {
                        onDeduplicate()
                    } label: {
                        HStack {
                            Text("Deduplicate Activities")
                            if isDeduplicating {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isResyncing || isDeduplicating)
                } footer: {
                    Text("Force Full Resync re-imports every activity from HealthKit from scratch. Use this if an activity's sport or name looks wrong after an app update. Deduplicate Activities removes any duplicate activities left over from an older version of the app.")
                }
            }
            .navigationTitle("Athlete")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .confirmationDialog(
                "Re-import your entire activity history from HealthKit?",
                isPresented: $isConfirmingResync,
                titleVisibility: .visible
            ) {
                Button("Force Full Resync", role: .destructive, action: onResync)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can take a while for a long training history.")
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
