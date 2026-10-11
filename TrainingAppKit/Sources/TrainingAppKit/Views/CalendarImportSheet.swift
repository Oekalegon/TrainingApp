import SwiftUI
import TrainingCore
import UniformTypeIdentifiers

/// The "Import Calendar" sheet (MVP2-103), opened from the week view toolbar: choose a Training
/// Calendar JSON file, see what importing it would do, then tap the checkmark to import. The X
/// closes the sheet; like the app's other sheets, the toolbar carries the actions.
struct CalendarImportSheet: View {
    @State var viewModel: CalendarImportViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingFile = false

    var body: some View {
        NavigationStack {
            Form {
                switch viewModel.state {
                case .idle:
                    chooseSection(message: nil)
                case .loading, .importing:
                    Section { ProgressView(viewModel.state == .importing ? "Importing…" : "Reading the file…") }
                case .preview(let fileName, let report):
                    summarySection(title: fileName, report: report, future: true)
                    chooseAnotherSection
                case .imported(let report):
                    summarySection(title: "Imported", report: report, future: false)
                case .failed(let message):
                    chooseSection(message: message)
                }
            }
            .navigationTitle("Import Calendar")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if case .imported = viewModel.state {
                        Button("Done") { dismiss() }
                    } else {
                        Button {
                            Task { await viewModel.performImport() }
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .accessibilityLabel("Import")
                        .disabled(!viewModel.canImport)
                    }
                }
            }
            .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { Task { await viewModel.load(from: url) } }
            }
        }
    }

    private func chooseSection(message: String?) -> some View {
        Section {
            Button("Choose File…", systemImage: "doc") { isChoosingFile = true }
        } header: {
            Text("Training Calendar file")
        } footer: {
            if let message {
                Text(message).foregroundStyle(.red)
            } else {
                Text("Choose a JSON file made by Export Calendar. Planned workouts are added with their steps. Completed activities aren't imported: they come from Health. Daily fitness numbers aren't imported either: they are recalculated.")
            }
        }
    }

    private var chooseAnotherSection: some View {
        Section {
            Button("Choose Another File…", systemImage: "doc") { isChoosingFile = true }
        }
    }

    @ViewBuilder
    private func summarySection(title: String, report: CalendarImportReport, future: Bool) -> some View {
        Section {
            row(future ? "Will be added" : "Added", count: report.added)
            row("Already in your calendar", count: report.skippedDuplicates)
            row("Before today (skipped)", count: report.skippedPast)
            row("Completed activities (not imported)", count: report.skippedCompleted)
            ForEach(report.templateRows(future: future), id: \.title) { row($0.title, count: $0.count) }
        } header: {
            Text(title)
        } footer: {
            if let message = viewModel.importError {
                Text(message).foregroundStyle(.red)
            } else if !future, report.added > 0 {
                Text("The workouts aren't sent to your Watch yet. They will be when Apple Fitness syncing is added.")
            }
        }
        if !report.rejected.isEmpty {
            Section("Can't be imported") {
                ForEach(Array(report.rejected.enumerated()), id: \.offset) { _, rejection in
                    VStack(alignment: .leading) {
                        Text(rejection.name ?? "Workout")
                        Text("\(rejection.date): \(rejection.reason.explanation)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func row(_ title: String, count: Int) -> some View {
        LabeledContent(title) {
            Text(count.formatted()).monospacedDigit()
        }
    }
}
