import SwiftUI
import TrainingCore

/// A planned activity that hasn't been reconciled to a completed one yet (MVP2-37) — same layout
/// and silhouette as `ActivityCard` (sport icon, name, expected load, then duration or distance),
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
/// Tapping it (MVP2-38) presents the planned-workout detail sheet — see `WeekView`'s
/// `.sheet(item: $selectedPlan)`. Expected values are shown plainly (no "~"), since the marker
/// already says "planned".
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
                                Text(load.formatted(TimelineCardStyle.loadFormat))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                    if let extentText {
                        extentText
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    private var extentText: Text? {
        switch summary.extent {
        case .duration(let seconds):
            Text(TimelineCardStyle.durationText(seconds))
        case .distance(let meters):
            Text(TimelineCardStyle.distanceText(meters: meters))
        case nil:
            nil
        }
    }

    private var accessibilityLabel: String {
        var parts = ["\(isMissed ? "Missed" : "Planned"): \(summary.name ?? "Planned workout")"]
        if !isMissed, let load = summary.load, load.rounded() > 0 {
            parts.append("load \(load.formatted(TimelineCardStyle.loadFormat))")
        }
        switch summary.extent {
        case .duration(let seconds):
            parts.append(TimelineCardStyle.spokenDuration(seconds))
        case .distance(let meters):
            parts.append(TimelineCardStyle.spokenDistance(meters: meters))
        case nil:
            break
        }
        if let intensity, !isMissed {
            parts.append(intensity.category.displayName.lowercased() + " intensity")
        }
        parts.append(isMissed ? "not done" : "not yet done")
        return parts.joined(separator: ", ")
    }
}
