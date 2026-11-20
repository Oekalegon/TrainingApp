import SwiftUI

@main
struct TrainingWatchApp: App {
    @State private var recorder = RunRecorder()

    var body: some Scene {
        WindowGroup {
            RunView(recorder: recorder)
        }
    }
}
