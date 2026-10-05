import SwiftUI
import TrainingCore

/// A planned activity that hasn't been reconciled to a completed one yet (MVP2-37) — same layout
/// and silhouette as `ActivityCard` (sport icon, name, expected load, then duration and distance),
/// over a plain fill like a completed card, distinguished by its intensity marker being an unfilled
/// "circle.circle" (MVP2-51) instead of `ActivityCard`'s solid filled circle — a small difference
/// that's what keeps it reading as "not done yet" at a glance (design doc §2.1) rather than a
/// second kind of completed activity. One already matched to a completed activity
/// (`completedActivityID != nil`) is skipped: the completed activity's own card above already
/// represents it.
///
/// On a day that has already passed (`isMissed`), a plan still without a completed activity was
/// missed, and the card is drawn differently: the plain view background with a secondary outline,
/// secondary text, no expected load, and no intensity marker — what was planned but didn't happen,
/// not something still to do.
///
/// A plan the Watch sync sent to the Apple Watch shows a small Watch symbol at the trailing end of
/// the second row, under the expected load, and one
/// whose workout can't go on the Watch shows a warning line with the reason (MVP2-119,
/// `PlannedCardContent.watchStatus`). Neither shows on a missed plan or while sending is off.
///
/// Tapping it (MVP2-38) presents the planned-workout detail sheet — see `WeekView`'s
/// `.sheet(item: $selectedPlan)`. A value the workout sets (a target duration or distance, a load
/// the athlete typed in) is shown plainly, since the marker already says "planned"; only an
/// estimate — the estimator's load, a duration or distance forecast from the athlete's paces —
/// carries a "~" (MVP2-8). Both duration and distance are shown, as on `ActivityCard`, whichever
/// the workout is defined by.
struct PlannedActivityCard: View {
    let plan: PlannedActivity
    /// The card's summary, intensity and missed state, from `WeekViewModel.plannedCardContent(for:)`.
    let content: WeekViewModel.PlannedCardContent
    let onSelect: () -> Void

    private var summary: WeekViewModel.PlannedCardSummary { content.summary }
    /// The workout's intended intensity (MVP2-43), shown as a small coloured ring leading the
    /// headline row — the counterpart of `ActivityCard`'s own filled-circle marker; `nil` leaves
    /// that slot empty.
    private var intensity: IntensityAssessment? { content.intensity }
    /// Whether this plan's day has passed without a completed activity matching it — drawn as an
    /// outlined card on the plain view background, with secondary text and no expected load: what
    /// was planned but didn't happen, not something still to do. Ignores `intensity`.
    private var isMissed: Bool { content.isMissed }
    /// Whether the Watch sync sent this plan to the Apple Watch (MVP2-119): a Watch symbol at the
    /// trailing end of the second row.
    private var isOnWatch: Bool { content.watchStatus == .onWatch }

    var body: some View {
        if plan.completedActivityID == nil {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: TimelineCardStyle.iconSpacing) {
                        // Reserves `intensityMarkerWidth` whether or not `intensity` is set (and
                        // never on a missed plan), so the sport icon lands at the same x as on
                        // `ActivityCard` and on a plan with no intensity yet.
                        Group {
                            if let intensity, !isMissed {
                                Image(systemName: "circle.circle")
                                    .foregroundStyle(intensity.tint)
                                    // Decorative — `accessibilityLabel` below already spells out the
                                    // intensity; without this, the symbol's own default label would
                                    // add a redundant "circle, circle" ahead of it.
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(width: TimelineCardStyle.intensityMarkerWidth)
                        Image(systemName: summary.sport.symbolName)
                            .foregroundStyle(isMissed ? .secondary : .primary)
                            .frame(width: TimelineCardStyle.iconWidth)
                        Text(summary.name ?? "Planned workout")
                            .bold()
                            .foregroundStyle(isMissed ? .secondary : .primary)
                        Spacer()
                        // No expected load on a missed workout: it never became training load.
                        if !isMissed, let load = summary.load, load.rounded() > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: TrainingMetricKind.load.icon)
                                Text(EstimateMarker.text(
                                    load.formatted(TimelineCardStyle.loadFormat), isEstimated: summary.isLoadEstimated
                                ))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                    // The duration and distance, with the Watch mark at the trailing end, under the
                    // expected load.
                    if extentText != nil || isOnWatch {
                        HStack {
                            extentText
                            Spacer()
                            if isOnWatch {
                                // Spoken in `accessibilityLabel` below.
                                Image(systemName: "applewatch")
                                    .accessibilityHidden(true)
                            }
                        }
                        // Monospaced digits, like `ActivityCard`'s second line.
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.leading, TimelineCardStyle.secondLineIndent)
                    }
                    if case .unsupported(let reason) = content.watchStatus {
                        // Orange only on the symbol: orange caption text is too faint on the card's
                        // light background.
                        Label {
                            Text(reason)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        .font(.caption)
                        .padding(.leading, TimelineCardStyle.secondLineIndent)
                    }
                }
                .padding(TimelineCardStyle.contentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if isMissed {
                        RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous)
                            .fill(weekViewBackground)
                        RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous)
                            .strokeBorder(Color.secondary, lineWidth: 0.5)
                    } else {
                        RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous)
                            .fill(TimelineCardStyle.background)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            // One element with the "planned" state spelled out — the marker is visual only.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Shows the workout's details")
            .accessibilityAddTraits(.isButton)
        }
    }

    /// "45:00   ~8.2 km": the expected duration and distance in `ActivityCard`'s second-line layout,
    /// the forecast one marked. The distance is left out when it can't be forecast.
    private var extentText: Text? {
        let duration = summary.duration.map {
            EstimateMarker.text(TimelineCardStyle.durationText($0), isEstimated: summary.isDurationEstimated)
        }
        let distance = summary.distanceMeters.map {
            EstimateMarker.text(TimelineCardStyle.distanceText(meters: $0), isEstimated: summary.isDistanceEstimated)
        }
        switch (duration, distance) {
        case (let duration?, let distance?):
            return Text("\(duration)\(TimelineCardStyle.partSpacing)\(distance)")
        case (let duration?, nil):
            return Text(duration)
        case (nil, let distance?):
            return Text(distance)
        case (nil, nil):
            return nil
        }
    }

    private var accessibilityLabel: String {
        var parts = ["\(isMissed ? "Missed" : "Planned"): \(summary.name ?? "Planned workout")"]
        if !isMissed, let load = summary.load, load.rounded() > 0 {
            parts.append("load " + EstimateMarker.spoken(load.formatted(TimelineCardStyle.loadFormat), isEstimated: summary.isLoadEstimated))
        }
        if let duration = summary.duration {
            parts.append(EstimateMarker.spoken(TimelineCardStyle.spokenDuration(duration), isEstimated: summary.isDurationEstimated))
        }
        if let distance = summary.distanceMeters {
            parts.append(EstimateMarker.spoken(TimelineCardStyle.spokenDistance(meters: distance), isEstimated: summary.isDistanceEstimated))
        }
        if let intensity, !isMissed {
            parts.append(intensity.category.displayName.lowercased() + " intensity")
        }
        parts.append(isMissed ? "not done" : "not yet done")
        switch content.watchStatus {
        case .onWatch:
            parts.append("on Apple Watch")
        case .unsupported(let reason):
            parts.append("can't go on Apple Watch: \(reason)")
        case nil:
            break
        }
        return parts.joined(separator: ", ")
    }
}
