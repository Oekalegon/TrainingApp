import SwiftUI
import TrainingCore

/// The step list of a structured workout (MVP2-143), drawn like the Fitness app's: each step an
/// outlined card with its role icon, name, what ends it and the zone it aims for, and a block that
/// repeats one "Repeat N" card holding its steps. Shared by the template detail and the creator, and
/// also used by the planned-workout views (MVP2-144).
struct WorkoutStepCardList: View {
    let blocks: [WorkoutBlockCard]
    /// The recorded step to highlight (MVP2-146): a step card that has one is a button that selects it,
    /// and tapping the selected one clears it. `nil` makes the cards plain, as in the template views.
    var selection: Binding<Int?>? = nil
    /// The stretch after the last step, as a card of its own below the steps (MVP2-146).
    var afterPlan: WorkoutAfterPlanCard? = nil

    var body: some View {
        VStack(spacing: 10) {
            ForEach(blocks) { block in
                if block.isGroup {
                    WorkoutRepeatCard(
                        steps: block.steps,
                        header: {
                            WorkoutRepeatHeader(
                                count: block.repetitions.formatted(), repetitionNumber: block.repetitionNumber,
                                parameterName: block.repetitionsParameterName
                            )
                        },
                        stepView: { card($0) },
                        footer: { EmptyView() }
                    )
                } else {
                    ForEach(block.steps) { card($0).cardStyle() }
                }
            }
            if let afterPlan {
                afterPlanCard(afterPlan).cardStyle()
            }
        }
    }

    /// The card for the time after the plan; a button that highlights its span like a step's.
    @ViewBuilder private func afterPlanCard(_ card: WorkoutAfterPlanCard) -> some View {
        let isSelected = selection?.wrappedValue == card.recordedStepID
        if let selection {
            Button {
                selection.wrappedValue = Self.toggled(selection.wrappedValue, tapping: card.recordedStepID)
            } label: {
                WorkoutAfterPlanCardView(card: card, isHighlighted: isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isSelected ? "Stops highlighting this stretch on the charts" : "Highlights this stretch on the charts")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            WorkoutAfterPlanCardView(card: card)
        }
    }

    /// What the highlighted step becomes when the card of step `id` is tapped (MVP2-146): that step,
    /// or none if it already was.
    static func toggled(_ current: Int?, tapping id: Int) -> Int? {
        current == id ? nil : id
    }

    /// A step's card; a button that highlights the step on the charts when it has a recorded step and
    /// the list has a selection.
    @ViewBuilder private func card(_ step: WorkoutStepCard) -> some View {
        let id = step.recordedStepID
        let isSelected = id != nil && selection?.wrappedValue == id
        if let selection, let id {
            Button {
                selection.wrappedValue = Self.toggled(selection.wrappedValue, tapping: id)
            } label: {
                WorkoutStepCardView(step: step, isHighlighted: isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isSelected ? "Stops highlighting this step on the charts" : "Highlights this step on the charts")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            WorkoutStepCardView(step: step)
        }
    }
}

/// A "Steps" section of a `Form` or `List` holding the step cards on the plain background, shared by
/// the template detail, the planned-workout sheet and the activity detail's linked plan (MVP2-144). The enclosing list sets
/// `defaultMinListRowHeight` to 1, or the spacer rows (``WorkoutStepListSpacerRow``) grow to the
/// default row height.
struct WorkoutStepCardSection: View {
    let blocks: [WorkoutBlockCard]
    var title: LocalizedStringKey = "Steps"
    /// The recorded step highlighted on the activity's charts; see ``WorkoutStepCardList/selection``.
    var selection: Binding<Int?>? = nil
    /// The stretch after the last step; see ``WorkoutStepCardList/afterPlan``.
    var afterPlan: WorkoutAfterPlanCard? = nil

    var body: some View {
        Section(title) {
            WorkoutStepListSpacerRow()
            WorkoutStepCardList(blocks: blocks, selection: selection, afterPlan: afterPlan)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            WorkoutStepListSpacerRow()
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
    init(repetitions: String, repetitionNumber: Int? = nil, parameterName: String? = nil, steps: [WorkoutStepCard]) {
        self.init(
            steps: steps,
            header: {
                WorkoutRepeatHeader(count: repetitions, repetitionNumber: repetitionNumber, parameterName: parameterName)
            },
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
    /// Which repetition this card is, when a repeat is shown one card per repetition (MVP2-146):
    /// the header then reads "Repeat 2 of 5".
    var repetitionNumber: Int? = nil
    /// The parameter that sets the count, shown in place of it; `nil` for a fixed count.
    var parameterName: String? = nil

    var body: some View {
        HStack {
            Text(repetitionNumber.map { "Repeat \($0) of \(count)" } ?? "Repeat")
            Spacer()
            Image(systemName: "repeat")
                .accessibilityHidden(true)
            if repetitionNumber != nil {
                EmptyView()
            } else if let parameterName {
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
        .accessibilityLabel(
            repetitionNumber.map { "Repeat \($0) of \(count)" }
                ?? parameterName.map { "Repeat \($0), a parameter" } ?? "Repeat \(count) times"
        )
    }
}

/// One step: role icon, name and what ends it on the left, the intensity target on the right.
struct WorkoutStepCardView: View {
    let step: WorkoutStepCard
    /// Whether this is the step highlighted on the charts (MVP2-146): tinted so it reads as selected.
    var isHighlighted = false

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
                // What was recorded (MVP2-146), in the title's column, so it lines up with the title.
                if let actual = step.actual {
                    WorkoutStepActualFigures(actual: actual)
                        .padding(.top, 6)
                } else if step.isNotRecorded {
                    Text("Not recorded")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ([step.title, step.parameterName.map { "\($0), a parameter" } ?? step.detail, step.target]
                .compactMap { $0 } + (step.actual.map(\.spokenText) ?? (step.isNotRecorded ? ["not recorded"] : [])))
                .joined(separator: ", ")
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
