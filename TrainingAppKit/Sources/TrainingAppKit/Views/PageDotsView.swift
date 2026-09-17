import SwiftUI

/// A small page-indicator dot row, shared by every hand-rolled carousel in this app
/// (`GraphPanelPagerView`/`GraphPanelStaticPreview`'s week-graph panel, `SportStatsPagerView`,
/// `HeartRateZoneDetailView`'s chart card) so a change to the dot styling can't drift between them.
/// `unhighlightedPillBackground` (6% opacity) is tuned for a large fill behind contrasting text
/// elsewhere in the day list — at this dot's tiny 5pt size that reads as nearly invisible, leaving
/// what looks like a single dot rather than a page indicator, hence the higher, dedicated 25%
/// opacity here instead.
struct PageDotsView: View {
    let count: Int
    let selectedIndex: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == selectedIndex ? Color.primary : Color.primary.opacity(0.25))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}
