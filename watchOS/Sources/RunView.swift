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
        case .starting, .saving:
            ProgressView()
        case .running, .paused:
            RunPages(recorder: recorder)
        case .saved:
            VStack {
                Text("Saved to Health")
                if let note = recorder.routeNote {
                    Text(note).font(.footnote)
                }
                Button("Done") { recorder.reset() }
            }
        case .failed(let message):
            ScrollView {
                VStack {
                    Text(message).font(.footnote)
                    if recorder.canRetrySave {
                        Button("Try saving again") { Task { await recorder.retrySave() } }
                        Button("Discard run", role: .destructive) { recorder.reset() }
                    } else {
                        Button("Try again") { recorder.reset() }
                    }
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

/// The metrics page: elapsed time, heart rate and distance. Units follow the system's region for
/// now; the athlete's own setting comes with the zone sync (WATCH-102).
private struct RunMetricsPage: View {
    let recorder: RunRecorder

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Duration.seconds(recorder.elapsed(at: context.date)),
                     format: .time(pattern: .hourMinuteSecond))
                    .font(.title2.monospacedDigit())
                    .accessibilityLabel("Elapsed time")
            }
            Text(recorder.heartRate.map { "\(Int($0.rounded())) bpm" } ?? "-- bpm")
                .font(.title.monospacedDigit())
                .accessibilityLabel("Heart rate")
                .accessibilityValue(recorder.heartRate.map { "\(Int($0.rounded())) beats per minute" } ?? "no reading")
            Text(Measurement(value: recorder.distanceMeters, unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(2)))))
                .font(.footnote.monospacedDigit())
                .accessibilityLabel("Distance")
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

/// The controls page, one swipe to the right of the metrics. Ending asks first, since a mis-tap
/// would end and save the run.
private struct RunControlsPage: View {
    let recorder: RunRecorder
    @State private var confirmingEnd = false

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
            Button(role: .destructive) { confirmingEnd = true } label: {
                Label("End", systemImage: "xmark")
            }
        }
        .confirmationDialog("End this run?", isPresented: $confirmingEnd) {
            Button("End run", role: .destructive) { recorder.end() }
            Button("Keep going", role: .cancel) {}
        }
    }
}
