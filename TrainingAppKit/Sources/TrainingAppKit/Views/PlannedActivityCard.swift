import SwiftUI
import TrainingCore

/// A planned activity that hasn't been reconciled to a completed one yet (MVP2-37) — same layout
/// and silhouette as `ActivityCard` (sport icon, name, expected load, then duration or distance),
/// but over a diagonal hatch instead of a plain fill: the hatch is what keeps it reading as "not
/// done yet" at a glance (design doc §2.1) rather than a second kind of completed activity. One
/// already matched to a completed activity (`completedActivityID != nil`) is skipped: the
/// completed activity's own card above already represents it.
///
/// Not tappable yet: MVP2-38's detail sheet adds that. Expected values are shown plainly (no "~"),
/// since the hatch already says "planned".
struct PlannedActivityCard: View {
    let plan: PlannedActivity
    let summary: WeekViewModel.PlannedCardSummary

    var body: some View {
        if plan.completedActivityID == nil {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: TimelineCardStyle.iconSpacing) {
                    Image(systemName: summary.sport.symbolName)
                        .foregroundStyle(.primary)
                        .frame(width: TimelineCardStyle.iconWidth)
                    Text(summary.name ?? "Planned workout")
                        .foregroundStyle(.primary)
                    Spacer()
                    if let load = summary.load, load.rounded() > 0 {
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
                RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous)
                    .fill(TimelineCardStyle.background)
                HatchPattern()
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 4)
                    .clipShape(RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous))
            }
            // One element with the "planned" state spelled out — the hatch is visual only.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var extentText: Text? {
        switch summary.extent {
        case .duration(let seconds):
            Text(Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond)))
        case .distance(let meters):
            Text(Measurement(value: meters, unit: UnitLength.meters).formatted(TimelineCardStyle.measurementFormat))
        case nil:
            nil
        }
    }

    private var accessibilityLabel: String {
        var parts = ["Planned: \(summary.name ?? "Planned workout")"]
        if let load = summary.load, load.rounded() > 0 {
            parts.append("load \(load.formatted(TimelineCardStyle.loadFormat))")
        }
        switch summary.extent {
        case .duration(let seconds):
            parts.append(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .wide)))
        case .distance(let meters):
            parts.append(Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .wide)))
        case nil:
            break
        }
        parts.append("not yet done")
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
