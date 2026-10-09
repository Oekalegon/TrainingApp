import SwiftUI
import TrainingCore

/// The step list of a structured workout (MVP2-143), drawn like the Fitness app's: each step an
/// outlined card with its role icon, name, what ends it and the zone it aims for, and a block that
/// repeats one "Repeat N" card holding its steps. Shared by the template detail and the creator, and
/// built to serve the planned-workout views too (MVP2-144).
struct WorkoutStepCardList: View {
    let blocks: [WorkoutBlockCard]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(blocks) { block in
                if block.isGroup {
                    WorkoutRepeatCard(repetitions: block.repetitions.formatted(), parameterName: block.repetitionsParameterName, steps: block.steps)
                } else {
                    ForEach(block.steps) { WorkoutStepCardView(step: $0).cardStyle() }
                }
            }
        }
    }
}

/// A "Repeat N" card: a header with the repeat count, then the block's steps divided by lines. The
/// editor supplies its own header, step views and footer (the block's "Add Step" row), so they can be
/// buttons.
struct WorkoutRepeatCard<Header: View, StepView: View, Footer: View>: View {
    let header: Header
    let steps: [WorkoutStepCard]
    let stepView: (WorkoutStepCard) -> StepView
    let footer: Footer

    init(
        steps: [WorkoutStepCard], @ViewBuilder header: () -> Header,
        @ViewBuilder stepView: @escaping (WorkoutStepCard) -> StepView,
        @ViewBuilder footer: () -> Footer
    ) {
        self.header = header()
        self.steps = steps
        self.stepView = stepView
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(steps) { step in
                WorkoutCardDivider()
                stepView(step)
            }
            footer
        }
        .cardStyle()
    }
}

extension WorkoutRepeatCard where Header == WorkoutRepeatHeader, StepView == WorkoutStepCardView, Footer == EmptyView {
    /// The read-only card: "Repeat" with `repetitions`, then plain steps.
    init(repetitions: String, parameterName: String? = nil, steps: [WorkoutStepCard]) {
        self.init(
            steps: steps, header: { WorkoutRepeatHeader(count: repetitions, parameterName: parameterName) },
            stepView: { WorkoutStepCardView(step: $0) }, footer: { EmptyView() }
        )
    }
}

/// The creator's "+ Add Step" / "+ Add Repeat" row, after the Fitness app's: a full-width card with a
/// purple symbol and label.
struct WorkoutAddCardLabel: View {
    let title: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.title3)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

/// The header of a repeat card: "Repeat" and the count beside the repeat symbol.
struct WorkoutRepeatHeader: View {
    /// The count as written, e.g. "5".
    let count: String
    /// The parameter that sets the count, shown in place of it; `nil` for a fixed count.
    var parameterName: String? = nil

    var body: some View {
        HStack {
            Text("Repeat")
            Spacer()
            Image(systemName: "repeat")
                .accessibilityHidden(true)
            if let parameterName {
                // Smaller than the "Repeat" label: it names the parameter, the count isn't shown.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: WorkoutBlockCard.parameterSymbol)
                        .accessibilityHidden(true)
                    Text(parameterName)
                }
                .font(.subheadline)
            } else {
                Text(count)
            }
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // The whole row, not just the text and the symbol, so the editor's tap target is the header.
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(parameterName.map { "Repeat \($0), a parameter" } ?? "Repeat \(count) times")
    }
}

/// One step: role icon, name and what ends it on the left, the intensity target on the right.
struct WorkoutStepCardView: View {
    let step: WorkoutStepCard

    var body: some View {
        // The icon is lined up with the title's first line and drawn at its size, not centred on the card.
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: step.kind.symbolName)
                .font(.headline)
                .foregroundStyle(step.end.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.headline)
                // What ends the step on the left and its target on the right, on one line of one
                // size, so they share a baseline rather than the target centring on the whole card.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let parameterName = step.parameterName {
                        // Set by a template parameter: say which, not what it starts at.
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Image(systemName: WorkoutBlockCard.parameterSymbol)
                                .accessibilityHidden(true)
                            Text(parameterName)
                        }
                    } else {
                        Text(step.detail)
                    }
                    Spacer(minLength: 8)
                    if let target = step.target {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            if let symbol = step.targetSymbol {
                                Image(systemName: symbol)
                                    .accessibilityHidden(true)
                            }
                            Text(target)
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [step.title, step.parameterName.map { "\($0), a parameter" } ?? step.detail, step.target]
                .compactMap { $0 }.joined(separator: ", ")
        )
    }
}

extension View {
    /// The outlined rounded card the step list is made of.
    func cardStyle() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.secondary.opacity(0.08))
            )
            // Inside the edge (`strokeBorder`), not centred on it: a list row clips its content, which
            // halved the left and right sides of a centred stroke. `primary` keeps it visible on a
            // light card as well as a dark one.
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
            )
    }
}

extension StepKind {
    /// An SF Symbol for the role, after the Fitness app's: solid double chevrons up for effort and down
    /// for recovery, dotted double chevrons pointing up-right for the warm-up and down-right for the
    /// cool-down.
    var symbolName: String {
        switch self {
        case .warmup: "chevron.up.right.dotted.2"
        case .work: "chevron.up.2"
        case .recovery: "chevron.down.2"
        case .cooldown: "chevron.down.right.dotted.2"
        }
    }
}

extension WorkoutStepCard.End {
    /// The icon's colour: yellow for a duration, blue for a distance and green for an open step, as in
    /// the Fitness app. The detail line beside it says the same, so colour is never the only cue.
    var tint: Color {
        switch self {
        case .time: .yellow
        case .distance: .blue
        case .open: .green
        }
    }
}

/// An invisible, one-point list row to put before and after a list of step cards.
///
/// A grouped list rounds and clips the first row of a section at its top corners and the last at its
/// bottom corners, even with a clear background, which thinned the border of the first and last card
/// at those corners. With a spacer row at each end, no card is the first or last row.
struct WorkoutStepListSpacerRow: View {
    var body: some View {
        Color.clear
            .frame(height: 1)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityHidden(true)
    }
}

/// The line between the parts of a repeat card: the header, each step and the "Add Step" row. A full
/// point thick and in the card border's colour, so it reads as part of the card rather than as the
/// hairline of an ordinary list.
struct WorkoutCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.22))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
