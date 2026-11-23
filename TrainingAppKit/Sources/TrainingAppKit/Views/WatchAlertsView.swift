import SwiftUI
import TrainingWatchKit

/// Apple Watch ▸ Alerts During a Run (WATCH-107): how the watch tells the athlete things during a
/// run, with sound, haptics, and speech or tones. Changes go to the watch at once.
struct WatchAlertsView: View {
    let cues: WatchCueSync

    var body: some View {
        List {
            alerts
        }
        .navigationTitle(AthleteRoute.watchAlerts.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var alerts: some View {
        Section {
            Picker("Sound", selection: binding(\.sound)) {
                Text("Earbuds Only").tag(CueSettings.Sound.automatic)
                Text("Earbuds + Speaker").tag(CueSettings.Sound.always)
                Text("Off").tag(CueSettings.Sound.never)
            }
            Picker("Haptics", selection: binding(\.haptics)) {
                Text("Automatic").tag(CueSettings.Haptics.automatic)
                Text("Always").tag(CueSettings.Haptics.always)
                Text("Off").tag(CueSettings.Haptics.never)
            }
            Picker("Style", selection: binding(\.style)) {
                Text("Tones and Speech").tag(AudioCueStyle.speech)
                Text("Tones").tag(AudioCueStyle.tones)
            }
        } footer: {
            Text("""
                With earbuds, zone alerts are sound only and automatic haptics are for step changes, \
                the end of the workout and the battery. Without earbuds, or with sound off, a haptic \
                carries the alert. Podcasts pause and music is ducked while a sound plays.
                """)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CueSettings, Value>) -> Binding<Value> {
        Binding(
            get: { cues.settings[keyPath: keyPath] },
            set: { value in
                var settings = cues.settings
                settings[keyPath: keyPath] = value
                cues.update(settings)
            })
    }
}
