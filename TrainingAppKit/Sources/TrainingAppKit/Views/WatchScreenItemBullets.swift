import SwiftUI
import TrainingWatchKit

/// The items of a run screen as a bulleted list in a small font, one per line: what the lists of screens and of
/// standard screens say beside a screen's preview.
struct WatchScreenItemBullets: View {
    let items: [RunScreenItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").accessibilityHidden(true)
                    Text(item.title)
                }
                .font(.footnote)
            }
        }
    }
}
