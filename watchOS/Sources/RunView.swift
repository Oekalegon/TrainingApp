import SwiftUI
import TrainingCore
import TrainingWatchKit

/// The recording screen (WATCH-101): start, then pages for the metrics (`RunMetricsPage`, WATCH-105) and the controls. Today's
/// planned workouts are on the start screen and tapping one runs its steps (WATCH-104).
struct RunView: View {
    let recorder: RunRecorder
    let zoneStore: WatchZoneStore
    let planStore: WatchPlanStore

    var body: some View {
        #if targetEnvironment(simulator)
        content.simulatorTestHooks(recorder: recorder, planStore: planStore)
        #else
        content
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch recorder.phase {
        case .idle:
            ScrollView {
                VStack(spacing: 8) {
                    Button("Start run") { Task { await recorder.start() } }
                        .buttonStyle(.borderedProminent)
                    TodayWorkouts(planStore: planStore, recorder: recorder)
                }
            }
        case .starting, .saving:
            ProgressView()
        case .running, .paused:
            RunPages(recorder: recorder, zoneStore: zoneStore)
                // The temporary battery warning, over everything, in the battery's colour (WATCH-110).
                .overlay {
                    if let warning = recorder.batteryWarning {
                        BatteryWarningScreen(warning: warning) { recorder.dismissBatteryWarning() }
                            // A new, worse warning is a new screen, with its own first moment.
                            .id(warning)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: recorder.batteryWarning)
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

/// The pages of a run in progress. Like the Workout app, the controls (pause or resume, end, later
/// next step) sit one swipe to the side of the main page: the zone dial in a planned workout (WATCH-118),
/// otherwise the metrics.
private struct RunPages: View {
    let recorder: RunRecorder
    let zoneStore: WatchZoneStore
    @State private var page = Page.metrics

    private enum Page { case controls, zones, metrics }

    /// Whether a planned workout still has steps to run: the zone dial is for those.
    private var hasSteps: Bool { recorder.stepEngine.map { !$0.isFinished } ?? false }

    var body: some View {
        TabView(selection: $page) {
            RunControlsPage(recorder: recorder)
                .tag(Page.controls)
            // The target-zone dial is for a planned workout, and is the page it opens on (WATCH-118).
            if hasSteps {
                ZoneDialPage(recorder: recorder, zoneStore: zoneStore)
                    .tag(Page.zones)
            }
            RunMetricsPage(recorder: recorder, zoneStore: zoneStore)
                .tag(Page.metrics)
        }
        .tabViewStyle(.page)
        .onAppear { if hasSteps { page = .zones } }
        .onChange(of: hasSteps) { _, hasSteps in
            // The steps are set a moment after the run starts, and are used up when the last one ends.
            // Only a page that is going away, or the default one, is moved off: someone on the
            // controls page to pause or end the run stays there.
            if hasSteps, page == .metrics { page = .zones }
            if !hasSteps, page == .zones { page = .metrics }
        }
    }
}

/// The controls page, one swipe to the right of the metrics. Ending asks first, since a mis-tap
/// would end and save the run.
private struct RunControlsPage: View {
    let recorder: RunRecorder
    @State private var confirmingEnd = false

    var body: some View {
        ScrollView {
        VStack(spacing: 8) {
            Button { Task { await recorder.lap() } } label: {
                Label(recorder.stepEngine?.isFinished == false ? "Next step" : "Lap", systemImage: "flag.fill")
            }
            .disabled(recorder.phase != .running)
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
            #if targetEnvironment(simulator)
            Text("fixes \(recorder.routePointCount), location \(recorder.locationDescription)").font(.caption2)
            Text("\(recorder.locationDiagnostics), events \(recorder.eventsWritten)").font(.system(size: 10))
            #endif
        }
        }
        .confirmationDialog("End this run?", isPresented: $confirmingEnd) {
            Button("End run", role: .destructive) { recorder.end() }
            Button("Keep going", role: .cancel) {}
        }
    }
}

/// Today's planned workouts, from the plan the iPhone sent (WATCH-103): each one's name and its
/// steps as short lines, and a note when the plan is old, so "no run planned" isn't mistaken for
/// "the phone hasn't said". Tapping a workout starts a run with its steps (WATCH-104); "Start run"
/// records a free run. The minute-by-minute timeline moves "today" on at midnight if the app stays open.
private struct TodayWorkouts: View {
    let planStore: WatchPlanStore
    let recorder: RunRecorder
    /// Speech or tones in earbuds (WATCH-107).
    @AppStorage(AudioCueStyle.defaultsKey) private var audioStyle = AudioCueStyle.speech
    @AppStorage(CueSettings.hapticsKey) private var haptics = CueSettings.Haptics.automatic
    @AppStorage(CueSettings.soundKey) private var sound = CueSettings.Sound.automatic

    var body: some View {
        // The timeline only makes the view redraw each minute; its own date is the schedule's, which
        // can lag, so the time shown against is read fresh.
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let now = Date.now
            let workouts = planStore.today(asOf: now)
            VStack(alignment: .leading, spacing: 6) {
                Text("Today")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                if planStore.plan == nil {
                    Text("No plan yet: open TrainingApp on your iPhone")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    if workouts.isEmpty {
                        Text("No run planned today").font(.footnote)
                    }
                    ForEach(workouts) { planned in
                        Button {
                            Task { await recorder.start(plan: planned) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(planned.name).font(.headline)
                                ForEach(Array(WatchWorkoutSummary.lines(for: planned.blocks).enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.system(size: 12))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityHint("Starts this workout")
                    }
                    if let note = planStore.staleNote(asOf: now) {
                        Text(note).font(.system(size: 11)).foregroundStyle(.orange)
                    }
                    Picker("Sound", selection: $sound) {
                        Text("Earbuds only").tag(CueSettings.Sound.automatic)
                        Text("Also speaker").tag(CueSettings.Sound.always)
                        Text("Off").tag(CueSettings.Sound.never)
                    }
                    Picker("Haptics", selection: $haptics) {
                        Text("Automatic").tag(CueSettings.Haptics.automatic)
                        Text("Always").tag(CueSettings.Haptics.always)
                        Text("Off").tag(CueSettings.Haptics.never)
                    }
                    Picker("Sound is", selection: $audioStyle) {
                        Text("Speech").tag(AudioCueStyle.speech)
                        Text("Tones").tag(AudioCueStyle.tones)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
