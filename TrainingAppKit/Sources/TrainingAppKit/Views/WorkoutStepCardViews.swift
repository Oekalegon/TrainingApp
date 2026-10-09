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
                    WorkoutRepeatCard(repetitions: block.repetitions.formatted(), steps: block.steps)
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
                Divider()
                stepView(step)
            }
            footer
        }
        .cardStyle()
    }
}

extension WorkoutRepeatCard where Header == WorkoutRepeatHeader, StepView == WorkoutStepCardView, Footer == EmptyView {
    /// The read-only card: "Repeat" with `repetitions`, then plain steps.
    init(repetitions: String, steps: [WorkoutStepCard]) {
        self.init(
            steps: steps, header: { WorkoutRepeatHeader(count: repetitions) },
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
    /// The count as written, e.g. "5", or a parameter's name in the editor.
    let count: String

    var body: some View {
        HStack {
            Text("Repeat")
            Spacer()
            Image(systemName: "repeat")
                .accessibilityHidden(true)
            Text(count)
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Repeat \(count) times")
    }
}

/// One step: role icon, name and what ends it on the left, the intensity target on the right.
struct WorkoutStepCardView: View {
    let step: WorkoutStepCard

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: step.kind.symbolName)
                .font(.title3)
                .foregroundStyle(step.kind.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.headline)
                Text(step.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let target = step.target {
                HStack(spacing: 4) {
                    Image(systemName: "scope")
                        .accessibilityHidden(true)
                    Text(target)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([step.title, step.detail, step.target].compactMap { $0 }.joined(separator: ", "))
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
    /// for recovery, dotted ones pointing up-right for the warm-up and down-right for the cool-down.
    var symbolName: String {
        switch self {
        case .warmup: "chevron.up.right.dotted.2"
        case .work: "chevron.up.2"
        case .recovery: "chevron.down.2"
        case .cooldown: "chevron.down.right.dotted.2"
        }
    }

    /// The role's colour; the name beside it always says the same, so colour is never the only cue.
    var tint: Color {
        switch self {
        case .warmup: .orange
        case .work: .green
        case .recovery: .yellow
        case .cooldown: .cyan
        }
    }
}
