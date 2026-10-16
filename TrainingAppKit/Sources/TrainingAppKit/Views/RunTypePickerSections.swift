import SwiftUI
import TrainingCore

/// The run types a plan prefers on each day of its micro-cycle (MVP5-112, MVP5 design doc §4a): one
/// row per micro day, with a chip per run type, several selectable per day. A plan setting, not an athlete
/// one, so the host (the Create Plan wizard) owns the ``RunTypePickerViewModel``.
///
/// Weekday names are shown beside the day for 7- and 14-day micros, not for 10-day ones, whose days
/// drift across the week. Chips wrap onto more lines at large Dynamic Type sizes, selection is not
/// by colour alone (a selected chip is filled and has a check mark and the selected trait). Meant to
/// sit inside a `List` or `Form`.
struct RunTypePickerSections: View {
    @Bindable var viewModel: RunTypePickerViewModel

    var body: some View {
        Section {
            ForEach(viewModel.days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(viewModel.title(forDay: day)).font(.headline)
                            if let weekday = viewModel.weekdayName(forDay: day) {
                                Text(weekday).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if !viewModel.namedTypes(onDay: day).isEmpty {
                            Button("Clear") { viewModel.clear(day: day) }
                                .buttonStyle(.borderless)
                                .font(.subheadline)
                                .accessibilityLabel("Clear run types for \(viewModel.accessibilityTitle(forDay: day))")
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(RunType.allCases, id: \.self) { type in
                            chip(type, day: day)
                        }
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .contain)
            }
        } header: {
            Text("Run Types per Day")
        } footer: {
            Text("Pick one or more types for the days that matter. A day with none lets the plan choose, and a type you pick only for some days stays off the others.")
        }
    }

    private func chip(_ type: RunType, day: Int) -> some View {
        let selected = viewModel.isNamed(type, onDay: day)
        return Button {
            viewModel.toggle(type, onDay: day)
        } label: {
            HStack(spacing: 4) {
                if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                Text(type.displayName).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? type.color : type.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(type.displayName), \(viewModel.accessibilityTitle(forDay: day))")
        .accessibilityAddTraits(selected ? [.isSelected, .isToggle] : .isToggle)
    }
}

#Preview("7-day micro") {
    List { RunTypePickerSections(viewModel: RunTypePickerViewModel(
        preferences: PlanPreferences(dayRunTypes: [2: [.interval, .threshold], 6: [.long]]), microLength: 7, firstWeekday: .monday)) }
}

#Preview("10-day micro, dark, large text") {
    List { RunTypePickerSections(viewModel: RunTypePickerViewModel(microLength: 10, firstWeekday: .monday)) }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
}
