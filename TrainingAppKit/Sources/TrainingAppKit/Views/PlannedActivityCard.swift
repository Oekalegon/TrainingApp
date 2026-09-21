import SwiftUI
import TrainingCore

/// A planned activity that hasn't been reconciled to a completed one yet (MVP2-37) — same layout
/// and silhouette as `ActivityCard` (sport icon, name, expected load, then duration or distance),
/// but over a diagonal hatch instead of a plain fill: the hatch is what keeps it reading as "not
/// done yet" at a glance (design doc §2.1) rather than a second kind of completed activity. One
/// already matched to a completed activity (`completedActivityID != nil`) is skipped: the
/// completed activity's own card above already represents it.
///
/// On a day that has already passed (`isMissed`), a plan still without a completed activity was
/// missed, and the card is drawn differently: the plain view background with a secondary outline,
/// secondary text, and no expected load, instead of the hatch.
///
/// Tapping it (MVP2-38) presents the planned-workout detail sheet — see `WeekView`'s
/// `.sheet(item: $selectedPlan)`. Expected values are shown plainly (no "~"), since the hatch
/// already says "planned".
struct PlannedActivityCard: View {
    let plan: PlannedActivity
    /// The card's summary, intensity and missed state, from `WeekViewModel.plannedCardContent(for:)`.
    let content: WeekViewModel.PlannedCardContent
    let onSelect: () -> Void

    private var summary: WeekViewModel.PlannedCardSummary { content.summary }
    /// The workout's intended intensity (MVP2-43), shown in the hatch stripes' colour, the
    /// counterpart of `ActivityCard`'s tinted background; `nil` keeps the grey hatch.
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
                        Image(systemName: summary.sport.symbolName)
                            .foregroundStyle(isMissed ? .secondary : .primary)
                            .frame(width: TimelineCardStyle.iconWidth)
                        Text(summary.name ?? "Planned workout")
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
                            .padding(.leading, TimelineCardStyle.iconWidth + TimelineCardStyle.iconSpacing)
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
                        // Only the stripes carry the intensity colour; the base stays the plain card
                        // fill, so a planned card reads as "not done yet" first and tinted second.
                        HatchPattern()
                            .stroke(intensity?.hatchTint ?? Color.secondary.opacity(0.10), lineWidth: 4)
                            .clipShape(RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            // One element with the "planned" state spelled out — the hatch is visual only.
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

/// Diagonal (45°) hatch lines filling a rect, spaced `spacing` apart — `PlannedActivityCard`'s
/// "not done yet" background. Stroke and clip it at the call site.
private struct HatchPattern: Shape {
    var spacing: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: rect.minX + x, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}
