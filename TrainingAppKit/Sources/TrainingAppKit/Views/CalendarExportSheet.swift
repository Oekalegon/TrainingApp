import SwiftUI
import TrainingCore

/// The "Export Calendar" sheet (MVP2-100), opened from the week view toolbar's share button:
/// choose a period, create the JSON export, then share it (Files, AirDrop, Mail and so on) through
/// the system share sheet.
struct CalendarExportSheet: View {
    @State var viewModel: CalendarExportViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Period") {
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
                }

                Section {
                    if let file = viewModel.exportedFile {
                        ShareLink(item: file) {
                            Label("Share Export", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            Task { await viewModel.export() }
                        } label: {
                            HStack {
                                Text("Create Export")
                                if viewModel.isExporting {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(!viewModel.isPeriodValid || viewModel.isExporting)
                    }
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .task { await viewModel.loadUpcomingRace() }
        }
    }
}
