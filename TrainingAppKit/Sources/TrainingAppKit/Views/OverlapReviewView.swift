import SwiftUI
import TrainingCore

/// A live count of how many activities currently have an overlap issue worth reviewing (MVP1-67)
/// — `AthleteView` shows this as the first row of its list, with a warning-color background,
/// whenever `WeekViewModel.overlapWarningCount` is non-zero. Unlike the one-time post-import
/// banner this replaced (MVP1-63), there's no dismiss action: the count is always current (it's
/// backed by the same live `overlapReviewItems`/`overlapWarningsByActivityID` set
/// `DayActivitiesSection`'s per-card badge reads), so it simply disappears on its own once every
/// overlap is resolved. Everything past "here's how many" (which pair, what to do about it) lives
/// behind `onReview`, in the activity detail sheet.
struct OverlapWarningBanner: View {
    let count: Int
    let onReview: () -> Void

    private var message: String {
        count == 1
            ? "1 activity has an overlap to review"
            : "\(count) activities have overlaps to review"
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
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The sheet `OverlapWarningBanner`'s tap opens (MVP1-63): every activity worth reviewing
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
        Group {
            if items.isEmpty {
                // Reachable if every overlap gets resolved elsewhere between the banner's tap and
                // this sheet's presentation -- rare, but a blank List with no explanation would
                // otherwise look broken rather than "nothing left to review".
                ContentUnavailableView(
                    "No Overlaps", systemImage: "checkmark.circle",
                    description: Text("Nothing left to review.")
                )
            } else {
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
            }
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
