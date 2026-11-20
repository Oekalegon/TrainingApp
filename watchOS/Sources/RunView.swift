import SwiftUI

/// The recording screen of WATCH-101: start, then pages for the metrics and the controls.
struct RunView: View {
    let recorder: RunRecorder

    var body: some View {
        content
            #if targetEnvironment(simulator)
            // `-autostart` lets a script start a run without tapping (simulator only).
            .task {
                if CommandLine.arguments.contains("-autostart"), recorder.phase == .idle {
                    await recorder.start()
                }
                // `-autoend <seconds>` ends the run after that long, for headless testing.
                if let index = CommandLine.arguments.firstIndex(of: "-autoend"),
                   index + 1 < CommandLine.arguments.count,
                   let seconds = Double(CommandLine.arguments[index + 1]) {
                    try? await Task.sleep(for: .seconds(seconds))
                    recorder.end()
                }
            }
            #endif
    }

    @ViewBuilder
    private var content: some View {
        switch recorder.phase {
        case .idle:
            Button("Start run") { Task { await recorder.start() } }
                .buttonStyle(.borderedProminent)
        case .running, .paused:
            RunPages(recorder: recorder)
        case .saved:
            VStack {
                Text("Saved to Health")
                Button("Done") { recorder.reset() }
            }
        case .failed(let message):
            ScrollView {
                VStack {
                    Text(message).font(.footnote)
                    Button("Try again") { recorder.reset() }
                }
            }
        }
    }
}

/// The pages of a run in progress. Like the Workout app, the metrics page is the default and the
/// controls (pause or resume, end, later next step) sit one swipe to the right.
private struct RunPages: View {
    let recorder: RunRecorder
    @State private var page = Page.metrics

    private enum Page { case controls, metrics }

    var body: some View {
        TabView(selection: $page) {
            RunControlsPage(recorder: recorder)
                .tag(Page.controls)
            RunMetricsPage(recorder: recorder)
                .tag(Page.metrics)
        }
        .tabViewStyle(.page)
    }
}

private struct RunMetricsPage: View {
    let recorder: RunRecorder

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Duration.seconds(recorder.elapsed(at: context.date)),
                     format: .time(pattern: .hourMinuteSecond))
                    .font(.title2.monospacedDigit())
            }
            Text(recorder.heartRate.map { "\(Int($0.rounded())) bpm" } ?? "-- bpm")
                .font(.title.monospacedDigit())
            Text(String(format: "%.2f km", recorder.distanceMeters / 1000))
                .font(.footnote.monospacedDigit())
            if recorder.phase == .paused {
                Text("Paused").font(.footnote).foregroundStyle(.yellow)
            }
            #if targetEnvironment(simulator)
            Text("fixes \(recorder.routePointCount), location \(recorder.locationDescription)").font(.caption2)
            Text(recorder.locationDiagnostics).font(.system(size: 10))
            #endif
        }
    }
}

private struct RunControlsPage: View {
    let recorder: RunRecorder

    var body: some View {
        VStack(spacing: 8) {
            if recorder.phase == .paused {
                Button { recorder.resume() } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .tint(.green)
            } else {
                Button { recorder.pause() } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .tint(.yellow)
            }
            Button(role: .destructive) { recorder.end() } label: {
                Label("End", systemImage: "xmark")
            }
        }
    }
}
