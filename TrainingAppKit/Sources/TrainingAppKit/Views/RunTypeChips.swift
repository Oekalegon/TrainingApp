import SwiftUI
import TrainingCore

/// A wrapping, trailing-aligned row of one compact chip per ``RunType``, several selectable (MVP5-112), sized like
/// the segmented controls above it in Running Availability. Selection is not by colour alone: a selected
/// chip is filled, shows a check mark and has the selected trait. Chips wrap onto more lines when the text is
/// large.
struct RunTypeChips: View {
    /// The types shown as chosen.
    let selected: Set<RunType>
    /// The weekday, for VoiceOver ("Interval, Thursday").
    let dayName: String
    /// Called with the type that was tapped.
    let toggle: (RunType) -> Void

    var body: some View {
        TrailingFlowLayout(spacing: 6) {
            ForEach(RunType.allCases, id: \.self) { type in
                let isSelected = selected.contains(type)
                Button { toggle(type) } label: {
                    HStack(spacing: 3) {
                        if isSelected { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
                        Text(type.displayName).lineLimit(1)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(isSelected ? type.color : type.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                .accessibilityLabel("\(type.displayName), \(dayName)")
                .accessibilityAddTraits(isSelected ? [.isSelected, .isToggle] : .isToggle)
            }
        }
    }
}

/// Lays subviews out in rows that fill from the trailing edge and wrap when the next one does not fit.
private struct TrailingFlowLayout: Layout {
    var spacing: CGFloat

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var used: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = size.width + (rows[rows.count - 1].isEmpty ? 0 : spacing)
            if used + needed > width, !rows[rows.count - 1].isEmpty {
                rows.append([index]); used = size.width
            } else {
                rows[rows.count - 1].append(index); used += needed
            }
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(subviews, width: width)
        let heights = rows.map { $0.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0 }
        return CGSize(width: width.isFinite ? width : 0, height: heights.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let sizes = row.map { subviews[$0].sizeThatFits(.unspecified) }
            var x = bounds.maxX
            for (offset, index) in row.enumerated().reversed() {
                x -= sizes[offset].width
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x -= spacing
            }
            y += (sizes.map(\.height).max() ?? 0) + spacing
        }
    }
}

#Preview("Chips, dark, large text") {
    List { RunTypeChips(selected: [.interval, .threshold], dayName: "Thursday") { _ in } }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
}
