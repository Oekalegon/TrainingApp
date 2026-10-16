import SwiftUI
import TrainingCore

/// A wrapping grid of one chip per ``RunType``, several selectable (MVP5-112). Selection is not by colour alone: a
/// selected chip is filled, shows a check mark and has the selected trait. Chips are at least 44 pt high and
/// wrap onto more lines at large Dynamic Type sizes.
struct RunTypeChips: View {
    /// The types shown as chosen.
    let selected: Set<RunType>
    /// The weekday, for VoiceOver ("Interval, Thursday").
    let dayName: String
    /// Called with the type that was tapped.
    let toggle: (RunType) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(RunType.allCases, id: \.self) { type in
                let isSelected = selected.contains(type)
                Button { toggle(type) } label: {
                    HStack(spacing: 4) {
                        if isSelected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                        Text(type.displayName).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(isSelected ? type.color : type.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(type.displayName), \(dayName)")
                .accessibilityAddTraits(isSelected ? [.isSelected, .isToggle] : .isToggle)
            }
        }
    }
}

#Preview("Chips, dark, large text") {
    List { RunTypeChips(selected: [.interval, .threshold], dayName: "Thursday") { _ in } }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
}
