import SwiftUI

/// The peak weekly volume of a plan (MVP5-112, MVP5 design doc §4a): a measure (distance, time or TRIMP) and a number
/// per 7 days, which the generator scales for 10- and 14-day micros. Empty means no peak is set. A plan
/// setting, owned by the host. Meant to sit inside a `List` or `Form`.
struct PeakVolumeSection: View {
    @Binding var draft: PeakVolumeDraft

    var body: some View {
        Section {
            Picker("Measure", selection: Binding(get: { draft.measure }, set: { draft.setMeasure($0) })) {
                ForEach(PeakVolumeMeasure.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                TextField("Peak per week", text: $draft.text)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityLabel("Peak weekly volume")
                Text(draft.unitLabel).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if let message = draft.message {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Peak Weekly Volume")
        } footer: {
            Text("The most you want to reach in one week of 7 days. A 10- or 14-day micro-cycle is scaled to it. Leave empty to let the plan choose.")
        }
    }
}

#Preview {
    @Previewable @State var draft = PeakVolumeDraft(measure: .distance, text: "60")
    List { PeakVolumeSection(draft: $draft) }
}
