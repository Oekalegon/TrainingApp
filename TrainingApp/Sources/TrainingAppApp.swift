import SwiftUI
import TrainingAppKit

@main
struct TrainingAppApp: App {
    @State private var environment: TrainingAppEnvironment?

    var body: some Scene {
        WindowGroup {
            if let environment {
                WeekView(model: environment.model, refresher: environment)
            } else {
                LaunchingView(onReady: { environment = $0 })
            }
        }
    }
}

/// Builds the app's `TrainingAppEnvironment` asynchronously, then hands it back to
/// `TrainingAppApp`.
private struct LaunchingView: View {
    let onReady: (TrainingAppEnvironment) -> Void

    var body: some View {
        ProgressView("Loading…")
            .task {
                if let environment = try? await TrainingAppEnvironment.make() {
                    onReady(environment)
                }
            }
    }
}
