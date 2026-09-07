import SwiftUI
import TrainingAppKit
import TrainingCore

@main
struct TrainingAppApp: App {
    @State private var model: TrainingModel?

    var body: some Scene {
        WindowGroup {
            if let model {
                PlaceholderRootView()
                    .environment(model)
            } else {
                LaunchingView(onReady: { model = $0 })
            }
        }
    }
}

/// Builds the app's `TrainingModel` asynchronously, then hands it back to `TrainingAppApp`.
///
/// A minimal placeholder for MVP 1's week view (MVP1-15), which will replace it as the loading
/// state once the real screen exists.
private struct LaunchingView: View {
    let onReady: (TrainingModel) -> Void

    var body: some View {
        ProgressView("Loading…")
            .task {
                if let model = try? await TrainingAppEnvironment.makeModel() {
                    onReady(model)
                }
            }
    }
}

/// Stands in for the week view (MVP1-15) until it exists, so the app target has something to
/// build and run against.
private struct PlaceholderRootView: View {
    var body: some View {
        Text("TrainingApp")
            .font(.title)
    }
}
