import SwiftUI
import TrainingAppKit

/// Starts watching Health for new workouts at launch (MVP2-121). HealthKit's background delivery
/// launches the app for a new workout without ever showing a window, so this can't wait for the
/// launch view: it has to register the observer query as soon as the process starts.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { @MainActor in
            if let environment = try? await TrainingAppEnvironment.shared() {
                await environment.startWorkoutObservation()
            }
        }
        return true
    }
}

@main
struct TrainingAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment: TrainingAppEnvironment?

    var body: some Scene {
        WindowGroup {
            if let environment {
                AppTabView(model: environment.model, refresher: environment, watchSync: environment.watchSync)
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
                if let environment = try? await TrainingAppEnvironment.shared() {
                    onReady(environment)
                }
            }
    }
}
