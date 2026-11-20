import SwiftUI

/// The minimal recording screen of WATCH-101: start, live bpm and time, pause/resume and end.
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
                #if targetEnvironment(simulator)
                Text("fixes \(recorder.routePointCount)").font(.caption2)
                #endif
                HStack {
                    if recorder.phase == .paused {
                        Button("Resume") { recorder.resume() }
                    } else {
                        Button("Pause") { recorder.pause() }
                    }
                    Button("End", role: .destructive) { recorder.end() }
                }
            }
        case .saved:
            Text("Saved to Health")
        case .failed(let message):
            Text(message).font(.footnote)
        }
    }
}
