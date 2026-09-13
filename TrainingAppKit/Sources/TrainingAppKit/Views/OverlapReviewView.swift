import SwiftUI
import TrainingCore

/// A dismissible banner reporting how many activities an import just found overlap issues among
/// (MVP1-63) — `WeekView` shows this in a `.safeAreaInset(edge: .bottom)` right after
/// `refresh(asOf:)`/`connectHealthData(asOf:)`/`resyncActivities(asOf:)` populates
/// `WeekViewModel.overlapImportSummary`. Deliberately the only overlap surfacing that happens
/// automatically — the day list's own per-card badge is passive (`DayActivitiesSection`'s
/// `ActivityCard`), and everything past "here's how many" (which pair, what to do about it) lives
/// behind `onReview`, in the activity detail sheet.
struct OverlapImportSummaryBanner: View {
    let summary: OverlapImportSummary
    let onReview: () -> Void
    let onDismiss: () -> Void

    private var message: String {
        summary.activityCount == 1
            ? "1 activity has an overlap to review"
            : "\(summary.activityCount) activities have overlaps to review"
    }

    var body: some View {
        Button(action: onReview) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Otherwise this inner button's tap is swallowed by the outer one (both would fire
                // `onReview` instead of just `onDismiss`) — plain `Button`s don't nest their tap
                // targets like this on their own.
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
    }
}

/// The sheet `OverlapImportSummaryBanner`'s tap opens (MVP1-63): every activity worth reviewing
/// for an overlap issue, each row tappable to open that activity's own detail sheet — where
/// `ActivityDetailView`'s "Overlap" section offers the actual resolution actions.
struct OverlapReviewView: View {
    let items: [OverlapReviewItem]
    let timeZone: TimeZone
    let onSelect: (Activity) -> Void

    private static func dateFormat(timeZone: TimeZone) -> Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()
        format.timeZone = timeZone
        return format
    }

    var body: some View {
        List(items) { item in
            Button {
                onSelect(item.activity)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.activity.sport.displayName)
                            .foregroundStyle(.primary)
                        Text(item.activity.start, format: Self.dateFormat(timeZone: timeZone))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.recommendation.reviewLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Overlapping Activities")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Short label for `OverlapReviewView`'s rows — a condensed variant of
/// `OverlapRecommendation.warningLabel` (`DayActivitiesSection`'s own badge text), sized for a
/// trailing row label rather than a VoiceOver announcement.
private extension OverlapRecommendation {
    var reviewLabel: String {
        switch self {
        case .duplicate: "Duplicate"
        case .merge: "Merge"
        case .conflict: "Conflict"
        case .possibleMultisport: "Multisport?"
        }
    }
}
