import SwiftUI

/// Gets a map for an area (MVP4-102): says where it comes from and what it takes, waits for a yes, shows the progress and ends with
/// the map in the library. Nothing is downloaded before the athlete taps Download.
struct MapDownloadSheet: View {
    @State private var model: MapDownloadModel
    let area: MapArea
    @Environment(\.dismiss) private var dismiss

    init(model: MapDownloadModel, area: MapArea) {
        _model = State(initialValue: model)
        self.area = area
    }

    var body: some View {
        NavigationStack {
            Form { content }
                .navigationTitle("Download Map")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if case .running = model.state { EmptyView() } else { Button(isFinished ? "Done" : "Close") { dismiss() } }
                    }
                }
        }
        .interactiveDismissDisabled({ if case .running = model.state { true } else { false } }())
        .task { if case .idle = model.state { await model.prepare(area) } }
        .presentationDetents([.medium, .large])
    }

    private var isFinished: Bool {
        switch model.state {
        case .done, .alreadyCovered: true
        default: false
        }
    }

    @ViewBuilder
    private var content: some View {
        Section { LabeledContent("Map of", value: area.name) }
        switch model.state {
        case .idle, .planning:
            Section { HStack { ProgressView(); Text("Looking for a map…").padding(.leading, 8) } }
        case .alreadyCovered(let name):
            Section {
                Label("You already have \(name), which covers this area.", systemImage: "checkmark.circle").foregroundStyle(.green)
            }
        case .ready(let plan):
            ready(plan)
        case .running(let progress):
            running(progress)
        case .done(let name):
            Section {
                Label("\(name) is on your phone and selected.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .failed(let text):
            Section {
                Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Button("Try Again") { Task { await model.prepare(area) } }
            }
        }
    }

    @ViewBuilder
    private func ready(_ plan: MapDownloadPlan) -> some View {
        Section {
            switch plan.source {
            case .hosted(let map):
                LabeledContent("From", value: "Ready-made map")
                LabeledContent("Size", value: bytes(map.bytes))
            case .phoneBuild(let build):
                LabeledContent("From", value: "OpenStreetMap data")
                LabeledContent("Region files", value: build.regionNames.joined(separator: ", "))
                LabeledContent("To download", value: build.downloadBytes.map(bytes) ?? "Unknown")
                if let available = build.availableBytes { LabeledContent("Free space", value: bytes(available)) }
            }
        } footer: {
            if case .phoneBuild = plan.source {
                Text("There is no ready-made map for this area, so the phone downloads the OpenStreetMap data and builds the map itself. "
                    + "That can take a while: use Wi-Fi and keep the app open.")
            }
        }
        Section {
            Button("Download", systemImage: "arrow.down.circle") { model.start() }.disabled(!plan.fits)
            if !plan.fits { Text("There is not enough free space.").foregroundStyle(.red) }
        }
    }

    @ViewBuilder
    private func running(_ progress: MapDownloadProgress) -> some View {
        Section {
            Text(progress.phase == .downloading ? "Downloading…" : "Building the map…")
            if let fraction = progress.fraction { ProgressView(value: fraction) } else { ProgressView() }
            Button("Cancel", role: .destructive) { model.cancel() }
        } footer: {
            Text("The map is added when this is done. You can use the app meanwhile, but keep it open.")
        }
    }

    /// "1,2 GB", and "0 KB" where the system would say "Zero KB".
    private func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: count)
    }
}
