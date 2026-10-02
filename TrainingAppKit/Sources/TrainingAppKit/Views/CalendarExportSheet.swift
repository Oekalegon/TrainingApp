import SwiftUI
import TrainingCore

/// The "Export Calendar" sheet (MVP2-100), opened from the week view toolbar's share button:
/// choose a period, then tap the checkmark to create the JSON export and share it (Files, AirDrop,
/// Mail and so on) through the system share sheet. The X cancels. Like the app's other sheets, the
/// toolbar carries the actions, so the form itself has no buttons beyond the period presets.
struct CalendarExportSheet: View {
    @State var viewModel: CalendarExportViewModel
    @Environment(\.dismiss) private var dismiss
    /// The file being shared, while the system share sheet is up (iOS).
    @State private var sharedFile: SharedFile?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("From", selection: $viewModel.firstDay, displayedComponents: .date)
                    DatePicker("To", selection: $viewModel.lastDay, displayedComponents: .date)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(viewModel.presets) { preset in
                                Button(preset.title) { viewModel.apply(preset) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                } header: {
                    Text("Period")
                } footer: {
                    if !viewModel.isPeriodValid {
                        Text("The end date must be on or after the start date.")
                    } else if viewModel.exportFailed {
                        Text("The export couldn't be created. Please try again.")
                            .foregroundStyle(.red)
                    } else {
                        Text("A JSON file with one entry per day: completed and planned workouts (missed ones left out) with their TRIMP, type, name, duration and distance, plus the day's fitness, fatigue, form, monotony and strain.")
                    }
                }
            }
            .navigationTitle("Export Calendar")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Symbol-only, matching the app's other sheets (and Apple Health's), rather than
                // "Cancel"/"Done" text buttons.
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    confirmationButton
                }
            }
            .task { await viewModel.loadUpcomingRace() }
            #if os(iOS)
            .sheet(item: $sharedFile) { shared in
                ActivityView(url: shared.url) { completed in
                    sharedFile = nil
                    // Shared (or saved): the job is done. Cancelled: stay, so the period can be
                    // changed or the share tried again.
                    if completed { dismiss() }
                }
                .presentationDetents([.medium, .large])
            }
            #endif
        }
    }

    /// The checkmark: creates the export, then opens the share sheet.
    @ViewBuilder
    private var confirmationButton: some View {
        if viewModel.isExporting {
            ProgressView()
        } else {
            #if os(iOS)
            Button {
                Task {
                    await viewModel.export()
                    if let file = viewModel.exportedFile { sharedFile = SharedFile(url: file) }
                }
            } label: {
                Image(systemName: "checkmark")
            }
            .accessibilityLabel("Share Export")
            .disabled(!viewModel.isPeriodValid)
            #else
            // No system share sheet to present from code on macOS: create the file first, then
            // the checkmark becomes a share link for it.
            if let file = viewModel.exportedFile {
                ShareLink(item: file)
            } else {
                Button {
                    Task { await viewModel.export() }
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel("Create Export")
                .disabled(!viewModel.isPeriodValid)
            }
            #endif
        }
    }
}

/// A file offered to the share sheet; `Identifiable` so it can drive `.sheet(item:)`.
private struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

#if os(iOS)
/// The system share sheet for one file. `ShareLink` can't be triggered from code, and the export
/// is created by the toolbar's checkmark, so this presents `UIActivityViewController` once the
/// file exists.
private struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    /// Called when the share sheet closes; `true` if the athlete completed an action (sent, saved
    /// or copied the file), `false` if they cancelled.
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in onFinish(completed) }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
