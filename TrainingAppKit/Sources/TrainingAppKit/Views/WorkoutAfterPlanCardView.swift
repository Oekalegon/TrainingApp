import SwiftUI

/// The card for the stretch after the plan's last step (MVP2-146): the athlete went on past the
/// planned workout, so it is drawn like a step card but says what it is, with the same four figures.
struct WorkoutAfterPlanCardView: View {
    let card: WorkoutAfterPlanCard
    /// Whether this is the stretch highlighted on the charts: tinted, like a highlighted step.
    var isHighlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "arrow.forward.circle")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("After the plan")
                        .font(.headline)
                    Text("Beyond the planned steps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    WorkoutStepActualFigures(actual: card.actual)
                        .padding(.top, 6)
                }
            }
        }
        // The whole card width, like a step card (whose own spacer fills it).
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((["after the plan"] + card.actual.spokenText).joined(separator: ", "))
    }
}
