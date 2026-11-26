import SwiftUI
import TrainingCore
import TrainingWatchKit

/// The recording screen (WATCH-101): start, then the run's pages (`RunPages`: the metrics screens and the controls). Today's
/// planned workouts are on the start screen and tapping one runs its steps (WATCH-104).
struct RunView: View {
    let recorder: RunRecorder
    let zoneStore: WatchZoneStore
    let planStore: WatchPlanStore
    let screenStore: RunScreenStore

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
            RunPages(recorder: recorder, zoneStore: zoneStore, set: screenStore.set(for: recorder.runPlan))
                // For the battery warning below. The pages need it on themselves too: the pager hands
                // each one the system's own value.
                .fakeDimmable()
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

/// The pages of a run in progress. Like the Workout app, the controls (pause or resume, end, next
/// step) sit one swipe to the side of the data screens. The data screens are a vertical stack the
/// Digital Crown turns through: the screens of the athlete's `RunScreenSet` (WATCH-109), drawn by
/// `RunScreenPage`; a planned workout's default has the zone dial (WATCH-118) as its second screen. The
/// set is taken once, when the run's pages are built, so a set that arrives mid-run reaches the next
/// run. Which screen shows and when it moves is `RunScreenSelection`.
private struct RunPages: View {
    let recorder: RunRecorder
    let zoneStore: WatchZoneStore
    @State private var page = Page.data
    @State private var selection: RunScreenSelection

    init(recorder: RunRecorder, zoneStore: WatchZoneStore, set: RunScreenSet) {
        self.recorder = recorder
        self.zoneStore = zoneStore
        _selection = State(initialValue: RunScreenSelection(set: set, hasSteps: recorder.hasSteps))
    }

    /// The screens to show now: those that need steps only while the workout has some. The binding below
    /// answers with a screen that is shown, also for the moment between the steps ending and the
    /// selection moving off the dial.
    private var shown: [RunScreen] { selection.screens(hasSteps: recorder.hasSteps) }

    var body: some View {
        TabView(selection: $page) {
            RunControlsPage(recorder: recorder)
                .tag(Page.controls)
            TabView(selection: Binding(get: { shown.contains { $0.id == selection.current } ? selection.current : (shown.first?.id ?? "") }, set: { selection.select($0) })) {
                ForEach(shown) { screen in
                    WatchRunScreenPage(recorder: recorder, screen: screen, showsDoneNote: screen.id == shown.first?.id).fakeDimmable()
                        .tag(screen.id)
                }
            }
            .tabViewStyle(.verticalPage)
            // A paused run says so on every data screen, at the top left, clear of the clock at the right.
            .overlay(alignment: .topLeading) {
                if recorder.phase == .paused {
                    Text("PAUSED")
                        .font(RunMetricStyle.captionFont).foregroundStyle(.orange)
                        .padding(.leading, 8).padding(.top, 6)
                }
            }
            .tag(Page.data)
        }
        .tabViewStyle(.page)
        // The steps are set a moment after the run starts, and are used up when the last one ends.
        .onChange(of: recorder.hasSteps) { _, hasSteps in selection.stepsChanged(hasSteps: hasSteps) }
    }

    private enum Page { case controls, data }
}

/// The controls page, one swipe to the side of the data screens. Ending asks first, since a mis-tap
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
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
