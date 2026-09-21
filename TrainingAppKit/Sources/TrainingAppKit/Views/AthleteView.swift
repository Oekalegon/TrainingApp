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
    /// Every activity currently worth reviewing for an overlap issue (MVP1-67), live from
    /// `WeekViewModel.overlapReviewItems` — backs both ``OverlapWarningBanner`` (shown just below
    /// the avatar) and the review sheet it opens.
    let overlapReviewItems: [OverlapReviewItem]
    let athleteTimeZone: TimeZone
    let activityDetailViewModel: (Activity) -> ActivityDetailViewModel
    let onResolveOverlap: (UUID) async -> Void
    let onDeleteActivity: (Activity) async -> Void
    /// Join actions for the detail sheet (MVP1-80) — see `ActivityDetailView`.
    let onJoinActivities: (Activity, Activity) async -> Bool
    let onUnjoinActivity: (Activity) async -> Bool
    let loadJoinedComponents: (Activity) async -> [Activity]
    @State private var isConfirmingResync = false
    @State private var isConfirmingDeduplicate = false
    /// Whether the overlap-review sheet (MVP1-67), opened by tapping ``OverlapWarningBanner``, is
    /// presented.
    @State private var isShowingOverlapReview = false
    /// Set by a row tap in the overlap-review sheet, then consumed by that sheet's `onDismiss` to
    /// open `selectedActivity`'s own detail sheet — chained this way (rather than presenting the
    /// detail sheet directly from on top of the review sheet) since SwiftUI only reliably supports
    /// one sheet on a view at a time. Same pattern `WeekView` used before this moved here.
    @State private var pendingOverlapActivity: Activity?
    /// The activity currently shown in the detail sheet, or `nil` when none is presented.
    @State private var selectedActivity: Activity?

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

                // Live, not dismissible (MVP1-67) — always visible while any overlap is
                // outstanding, so it can never go stale the way the old post-import banner could.
                if !overlapReviewItems.isEmpty {
                    Section {
                        OverlapWarningBanner(count: overlapReviewItems.count) {
                            isShowingOverlapReview = true
                        }
                    }
                    .listRowBackground(Color.orange.opacity(0.15))
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

                    // Each zone's own bpm range under the settings above (MVP1-71) -- a separate
                    // section, not more rows in "Heart Rate Zones", since these five are a distinct
                    // reference table derived from those settings rather than another setting of
                    // their own. Same colored-dot-before-name treatment as the activity detail
                    // sheet's own zone list (MVP1-70), for the same `HeartRateZone.color` ramp.
                    if !viewModel.heartRateZoneRanges.isEmpty {
                        Section("Zones") {
                            ForEach(viewModel.heartRateZoneRanges) { zoneRange in
                                LabeledContent {
                                    Text(bpmRangeText(zoneRange.bpmRange))
                                } label: {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(zoneRange.zone.color)
                                            .frame(width: 8, height: 8)
                                            .accessibilityHidden(true)
                                        Text("Zone \(zoneRange.zone.rawValue)")
                                    }
                                }
                            }
                        }
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
                        isConfirmingDeduplicate = true
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
            .confirmationDialog(
                "Remove duplicate activities?",
                isPresented: $isConfirmingDeduplicate,
                titleVisibility: .visible
            ) {
                Button("Deduplicate Activities", role: .destructive, action: onDeduplicate)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Permanently removes duplicate activities left over from an older version of the app. This can't be undone.")
            }
            .sheet(item: $selectedActivity) { activity in
                // Its own NavigationStack: a sheet doesn't inherit the presenting view's
                // navigation bar. Same pattern as WeekView's own activity detail sheet.
                NavigationStack {
                    ActivityDetailView(
                        viewModel: activityDetailViewModel(activity),
                        onResolveOverlap: { id in await onResolveOverlap(id) },
                        onDelete: { await onDeleteActivity(activity) },
                        onJoin: { other in await onJoinActivities(activity, other) },
                        onUnjoin: { await onUnjoinActivity(activity) },
                        loadComponents: { await loadJoinedComponents(activity) }
                    )
                }
            }
            // Opens `pendingOverlapActivity`'s own detail sheet only once this one has actually
            // finished dismissing — see that property's own doc comment for why this two-step
            // handoff, rather than presenting straight from on top of this sheet.
            .sheet(
                isPresented: $isShowingOverlapReview,
                onDismiss: {
                    if let pendingOverlapActivity {
                        selectedActivity = pendingOverlapActivity
                        self.pendingOverlapActivity = nil
                    }
                }
            ) {
                NavigationStack {
                    OverlapReviewView(
                        items: overlapReviewItems,
                        timeZone: athleteTimeZone,
                        onSelect: { activity in
                            pendingOverlapActivity = activity
                            isShowingOverlapReview = false
                        }
                    )
                }
            }
        }
    }

    /// "120–133 bpm" — whole-number bpm on both ends, matching every other bpm figure on this
    /// screen (Resting/Max/Lactate Threshold above).
    private func bpmRangeText(_ range: ClosedRange<Double>) -> String {
        "\(Int(range.lowerBound.rounded()))–\(Int(range.upperBound.rounded())) bpm"
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
