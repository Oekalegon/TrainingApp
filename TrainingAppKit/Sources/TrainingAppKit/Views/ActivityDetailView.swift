import SwiftUI
import TrainingCore

/// The activity detail screen (design doc §2.2): text/stat rows only — no map/route, no
/// cadence/elevation charts in MVP 1.
struct ActivityDetailView: View {
    let viewModel: ActivityDetailViewModel
    /// Runs `WeekViewModel.resolveOverlap(deleting:)` for the given activity id (MVP1-63) —
    /// `WeekView` supplies this. `async` so the caller can await it before dismissing: whichever
    /// side of `viewModel.overlapContext` the athlete picks to delete, the sheet should only close
    /// once the delete has actually happened, not the instant the button is tapped.
    let onResolveOverlap: (UUID) async -> Void
    /// Runs `WeekViewModel.deleteActivity(_:asOf:)` (MVP1-65) — the bottom-of-list "Delete
    /// Activity" button's action, gated behind `isShowingDeleteConfirmation`'s alert. `async` for
    /// the same reason as `onResolveOverlap`: the caller awaits it before dismissing, rather than
    /// firing a detached `Task` and dismissing immediately regardless of whether the delete has
    /// actually run yet. Independent of `onResolveOverlap`: always available, not just when
    /// `viewModel.overlapContext` flags an issue.
    let onDelete: () async -> Void
    /// Runs `WeekViewModel.joinActivities(_:with:)` with the other piece of a
    /// ``OverlapRecommendation/join`` pair (MVP1-80). `async` for the same reason as
    /// `onResolveOverlap`: the sheet closes only once the join has actually happened.
    /// Returns whether the join happened; the sheet stays open (with a message) when it didn't.
    let onJoin: (Activity) async -> Bool
    /// Runs `WeekViewModel.unjoinActivity(_:)` for this (joined) activity (MVP1-80); same
    /// success/stay-open contract as `onJoin`.
    let onUnjoin: () async -> Bool
    /// Loads the pieces this activity was joined from — empty for an ordinary activity — for the
    /// "Joined from" section (MVP1-80).
    let loadComponents: () async -> [Activity]
    @Environment(\.dismiss) private var dismiss
    /// The pieces this activity was joined from, loaded once by `.task`; empty for an ordinary one.
    @State private var components: [Activity] = []
    /// Set when a join/unjoin was refused, so the sheet stays open and says so rather than
    /// closing as if it had worked.
    @State private var joinFailureMessage: String?
    /// Whether the "Delete Activity?" confirmation alert (MVP1-65) is presented — a destructive,
    /// irreversible-from-the-UI action, so it's never triggered directly from the bottom button.
    @State private var isShowingDeleteConfirmation = false

    private static func timeFormat(timeZone: TimeZone) -> Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.hour().minute()
        format.timeZone = timeZone
        return format
    }

    private var dateFormat: Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).hour().minute()
        format.timeZone = viewModel.timeZone
        return format
    }

    var body: some View {
        List {
            if let overlapContext = viewModel.overlapContext {
                Section("Overlap") {
                    OverlapSectionContent(
                        thisActivity: viewModel.activity,
                        context: overlapContext,
                        timeZone: viewModel.timeZone,
                        onResolve: { id in
                            Task {
                                await onResolveOverlap(id)
                                dismiss()
                            }
                        },
                        onJoin: {
                            Task {
                                if await onJoin(overlapContext.otherActivity) {
                                    dismiss()
                                } else {
                                    joinFailureMessage = "These activities couldn't be joined."
                                }
                            }
                        }
                    )
                    if let joinFailureMessage {
                        Text(joinFailureMessage).foregroundStyle(.red)
                    }
                }
            }

            if !components.isEmpty {
                Section {
                    ForEach(components) { piece in
                        LabeledContent(
                            piece.start.formatted(Self.timeFormat(timeZone: viewModel.timeZone)),
                            value: Duration.seconds(piece.duration).formatted(.time(pattern: .hourMinuteSecond))
                        )
                    }
                    Button("Unjoin Activities") {
                        Task {
                            if await onUnjoin() {
                                dismiss()
                            } else {
                                joinFailureMessage = "This activity couldn't be unjoined."
                            }
                        }
                    }
                    if let joinFailureMessage {
                        Text(joinFailureMessage).foregroundStyle(.red)
                    }
                } header: {
                    Text("Joined From")
                } footer: {
                    Text("This session was recorded in \(components.count) parts and is shown as one activity.")
                }
            }

            Section {
                LabeledContent("Start", value: viewModel.activity.start.formatted(dateFormat))
                LabeledContent("Duration", value: durationText)
                if let distanceMeters = viewModel.summary.distanceMeters {
                    LabeledContent("Distance", value: distanceText(distanceMeters))
                }
            }

            Section("Load") {
                if viewModel.summary.load.confidence > 0 {
                    LabeledContent("Training Load (TRIMP)", value: loadText)
                } else {
                    Text("Load could not be computed for this activity.")
                        .foregroundStyle(.secondary)
                }
            }

            if let averageHeartRateBPM = viewModel.summary.averageHeartRateBPM {
                Section("Heart Rate") {
                    LabeledContent("Average", value: "\(Int(averageHeartRateBPM.rounded())) bpm")
                }
            }

            if viewModel.summary.timeInZone.total > 0 {
                Section {
                    // Every zone 1...5, not just the ones this activity actually reached (MVP1-70)
                    // -- unlike the day list's/week pager's own zone-derived figures, this is meant
                    // to read as the full five-zone scale the athlete can compare a session against,
                    // not just a summary of what happened. Iterates `HeartRateZone.allCases`, not a
                    // bare `1...5`, so `zone.color` below never needs a fallback for an
                    // out-of-range raw value -- there isn't one to guard against.
                    ForEach(HeartRateZone.allCases, id: \.self) { zone in
                        let seconds = viewModel.summary.timeInZone.seconds[zone.rawValue] ?? 0
                        LabeledContent {
                            Text(zoneText(seconds: seconds, zone: zone.rawValue))
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(zone.color)
                                    .frame(width: 8, height: 8)
                                    // Decorative only -- the zone number right next to it already
                                    // says what VoiceOver needs; without this it would add a
                                    // second, unlabeled stop to the swipe order for every row.
                                    .accessibilityHidden(true)
                                Text("Zone \(zone.rawValue)")
                            }
                        }
                    }
                } header: {
                    Text("Time in Zone")
                } footer: {
                    // The same zone breakdown above, collapsed into the two-bucket 80/20
                    // (polarized-training) model (MVP1-48) -- zone 0 (below zone 1) and zones 1-2
                    // are "Low", zones 3-5 are "Moderate-High", matching
                    // `TimeInZone.polarizedSplit`'s own zone grouping. A footer under the same
                    // section, not a second `Section`, since it's a rollup of the rows above it
                    // rather than new information.
                    Text("\(lowPercentText) low, \(moderateToHighPercentText) moderate-to-high")
                }
            }

            // A centered red text button in its own section, not a toolbar icon (MVP1-65) --
            // matches the "Delete Account"-style destructive action at the bottom of a Settings
            // list, rather than a trash icon sitting next to everyday navigation controls.
            Section {
                Button("Delete Activity", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle(viewModel.activity.sport.displayName)
        .task { components = await loadComponents() }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Irreversible from the UI (MVP1-65) -- always confirmed, never triggered directly from
        // the bottom button.
        .alert("Delete Activity?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await onDelete()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private var durationText: String {
        Duration.seconds(viewModel.summary.movingTime).formatted(.units(allowed: [.hours, .minutes, .seconds]))
    }

    private func distanceText(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated))
    }

    private var loadText: String {
        viewModel.summary.load.value.formatted(.number.precision(.fractionLength(0)))
    }

    private func zoneText(seconds: TimeInterval, zone: Int) -> String {
        let duration = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes]))
        let fraction = viewModel.summary.timeInZone.fraction(of: zone)
        let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
        return "\(duration) (\(percent))"
    }

    private var polarizedSplit: PolarizedIntensitySplit {
        viewModel.summary.timeInZone.polarizedSplit
    }

    private var lowPercentText: String {
        polarizedSplit.lowFraction.formatted(.percent.precision(.fractionLength(0)))
    }

    private var moderateToHighPercentText: String {
        polarizedSplit.moderateToHighFraction.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// The "Overlap" section's content in `ActivityDetailView` (MVP1-63) — a plain-language
/// description of the issue plus resolution buttons, both driven by `context.recommendation`.
/// Split out from `ActivityDetailView.body` since a `switch` over all five recommendation types
/// reads more clearly as its own small view than inline in that `List`.
private struct OverlapSectionContent: View {
    /// The activity whose own detail sheet this section is inside — as distinct from
    /// `context.otherActivity`, the other side of the pair.
    let thisActivity: Activity
    let context: OverlapContext
    let timeZone: TimeZone
    /// Called with the id of whichever activity (`thisActivity` or `context.otherActivity`) the
    /// athlete picked to delete.
    let onResolve: (UUID) -> Void
    /// Called when the athlete accepts a ``OverlapRecommendation/join`` — combines `thisActivity`
    /// with `context.otherActivity` into one.
    let onJoin: () -> Void

    private static func timeFormat(timeZone: TimeZone) -> Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.hour().minute()
        format.timeZone = timeZone
        return format
    }

    /// "Cycling at 14:32" — names the other side of the pair for the section's description text.
    private var otherActivityDescription: Text {
        let time = Text(context.otherActivity.start, format: Self.timeFormat(timeZone: timeZone))
        return Text("\(context.otherActivity.sport.displayName) at \(time)")
    }

    var body: some View {
        switch context.recommendation {
        case .duplicate(_, let remove):
            Text("This looks like a duplicate of \(otherActivityDescription).")
                .foregroundStyle(.secondary)
            // `remove` already names the correct side regardless of whether `thisActivity` is the
            // one to keep or the one to remove — a single, pre-decided action, unlike
            // `.merge`/`.conflict` below, which need the athlete to pick.
            Button("Remove Duplicate", role: .destructive) {
                onResolve(remove)
            }
        case .merge:
            Text("This overlaps \(otherActivityDescription), but the data differs — pick which one to keep.")
                .foregroundStyle(.secondary)
            resolutionButtons
        case .conflict:
            Text(
                "This overlaps \(otherActivityDescription) — they likely describe the same session. Pick which one actually happened."
            )
            .foregroundStyle(.secondary)
            resolutionButtons
        case .join:
            Text(
                "This and \(otherActivityDescription) look like one session that was recorded in two parts."
            )
            .foregroundStyle(.secondary)
            Button("Join into One Activity", action: onJoin)
        case .possibleMultisport:
            Text(
                "This is close to \(otherActivityDescription) — likely a separate leg of the same multisport session. No action needed."
            )
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var resolutionButtons: some View {
        Button("Keep This, Delete Other") {
            onResolve(context.otherActivity.id)
        }
        Button("Keep Other, Delete This", role: .destructive) {
            onResolve(thisActivity.id)
        }
    }
}
