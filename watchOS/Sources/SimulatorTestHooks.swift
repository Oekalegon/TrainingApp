#if targetEnvironment(simulator)
import SwiftUI
import TrainingWatchKit

/// Launch arguments that drive a run in the simulator without tapping, for headless testing.
///
/// - `-autostart`: start a free run.
/// - `-autostartPlan`: start the first workout planned for today.
/// - `-autopause <after>,<for>`: pause after that many seconds, for that many seconds.
/// - `-autolap <after>`: press the lap button after that many seconds.
/// - `-autoend <seconds>`: end the run after that long.
private struct SimulatorTestHooks: ViewModifier {
    let recorder: RunRecorder
    let planStore: WatchPlanStore

    func body(content: Content) -> some View {
        content.task {
            let arguments = CommandLine.arguments
            if recorder.phase == .idle {
                if arguments.contains("-autostartPlan") {
                    // The plan may arrive (or be faked) a moment after this runs.
                    for _ in 0..<30 where planStore.today().isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
                    if let plan = planStore.today().first { await recorder.start(plan: plan) }
                } else if arguments.contains("-autostart") {
                    await recorder.start()
                }
            }
            if let parts = values(after: "-autopause"), parts.count == 2 {
                Task {
                    try? await Task.sleep(for: .seconds(parts[0]))
                    recorder.pause()
                    try? await Task.sleep(for: .seconds(parts[1]))
                    recorder.resume()
                }
            }
            if let seconds = values(after: "-autolap")?.first {
                Task {
                    try? await Task.sleep(for: .seconds(seconds))
                    await recorder.lap()
                }
            }
            if let seconds = values(after: "-autoend")?.first {
                try? await Task.sleep(for: .seconds(seconds))
                recorder.end()
            }
        }
    }

    /// The comma-separated numbers after `flag` in the launch arguments, if it is given.
    private func values(after flag: String) -> [Double]? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1].split(separator: ",").compactMap { Double($0) }
    }
}

extension View {
    /// Adds the simulator's launch-argument test hooks (see `SimulatorTestHooks`).
    func simulatorTestHooks(recorder: RunRecorder, planStore: WatchPlanStore) -> some View {
        modifier(SimulatorTestHooks(recorder: recorder, planStore: planStore))
    }
}
#endif
