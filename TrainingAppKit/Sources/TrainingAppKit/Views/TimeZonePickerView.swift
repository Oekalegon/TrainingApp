import SwiftUI

/// Picks the athlete's time zone from every identifier the system knows (MVP2-132), with a search
/// field. Choosing one saves it and goes back; a failed save keeps the screen open with a message.
struct TimeZonePickerView: View {
    let selected: TimeZone
    /// Saves the chosen zone; returns whether it worked.
    let onSelect: (TimeZone) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var isShowingError = false

    var body: some View {
        List(filteredIdentifiers, id: \.self) { identifier in
            Button {
                guard let timeZone = TimeZone(identifier: identifier) else { return }
                Task {
                    if await onSelect(timeZone) { dismiss() } else { isShowingError = true }
                }
            } label: {
                HStack {
                    Text(identifier.replacingOccurrences(of: "_", with: " "))
                    Spacer()
                    if identifier == selected.identifier {
                        Image(systemName: "checkmark")
                            .accessibilityLabel("Selected")
                    }
                }
            }
            .foregroundStyle(.primary)
        }
        .navigationTitle("Time Zone")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "City or region")
        .alert("Couldn't Save", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The time zone couldn't be saved. Try again.")
        }
    }

    /// Every known identifier, sorted, narrowed by the search text (spaces and underscores alike).
    private var filteredIdentifiers: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.sorted()
        let query = searchText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }
}
