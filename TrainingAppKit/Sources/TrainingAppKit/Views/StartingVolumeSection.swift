import SwiftUI

/// The weekly volume a plan starts from (MVP5-162): a number per 7 days in the measure of the peak, which the host
/// sets and pre-fills from the athlete's recent running. Meant to sit inside a `List` or `Form`.
struct StartingVolumeSection: View {
    @Binding var draft: PeakVolumeDraft

    var body: some View {
        Section {
            HStack {
                TextField("Starting volume per week", text: $draft.text)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityLabel("Starting weekly volume")
                Text(draft.unitLabel).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if let message = draft.message {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Starting Weekly Volume")
        } footer: {
            Text("What the plan's base starts from, in one week of 7 days. Filled in from your running of the last four weeks; change it if that isn't what you can do now.")
        }
    }
}
