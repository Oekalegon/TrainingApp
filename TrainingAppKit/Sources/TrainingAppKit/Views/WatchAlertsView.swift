import SwiftUI
import TrainingWatchKit

/// Apple Watch ▸ Alerts During a Run (WATCH-107): how the watch tells the athlete things during a
/// run. Where sound plays and when the wrist taps are set once; for each kind of signal (a step
/// starts, below the zone, back in the zone, …) tone and speech are two check boxes, so a signal can
/// have either, both (the tone first) or neither. Work steps can be announced before they start.
/// Changes go to the watch at once.
struct WatchAlertsView: View {
    let cues: WatchCueSync

    var body: some View {
        List {
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
            } footer: {
                Text("""
                    Automatic haptics are for step changes, the end of the workout and the battery. A zone \
                    alert taps only when it has no sound. Podcasts pause and music is ducked while a sound plays.
                    """)
            }
            ForEach(SignalKind.allCases) { kind in
                Section {
                    Toggle("Tone", isOn: signalBinding(kind, \.tone))
                    Toggle("Speech", isOn: signalBinding(kind, \.speech))
                } header: {
                    Text(kind.title)
                } footer: {
                    if kind == .stepStart {
                        Text("The tone counts down the last 5 seconds of a step, one short tone a second, and is longer as the next step starts.")
                    }
                }
                .toggleStyle(CheckBoxToggleStyle())
            }
            Section {
                Toggle("Announce Work Steps Ahead", isOn: binding(\.announceWorkAhead))
                if cues.settings.announceWorkAhead {
                    Stepper(
                        "\(cues.settings.aheadSeconds) Seconds Before",
                        value: binding(\.aheadSeconds), in: 5...30, step: 5)
                }
            } header: {
                Text("Step Announcements")
            } footer: {
                Text("""
                    A work step is announced before it starts ("Next: work for 4 minutes, zone 4") \
                    when the step before it has a time goal. Other steps, and ones that can't be foreseen, \
                    are announced as they start, if Speech is on for Step Starts.
                    """)
            }
        }
        .navigationTitle(AthleteRoute.watchAlerts.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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

    private func signalBinding(_ kind: SignalKind, _ keyPath: WritableKeyPath<SignalSound, Bool>) -> Binding<Bool> {
        Binding(
            get: { cues.settings[kind][keyPath: keyPath] },
            set: { value in
                var settings = cues.settings
                settings[kind][keyPath: keyPath] = value
                cues.update(settings)
            })
    }
}

/// A check box with its label, for settings that are on or off independently of each other.
private struct CheckBoxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer()
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn ? Color.accentColor : Color.secondary)
                    .imageScale(.large)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
