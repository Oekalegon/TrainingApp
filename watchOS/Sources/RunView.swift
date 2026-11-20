import SwiftUI
import TrainingCore
import TrainingWatchKit

/// The recording screen (WATCH-101): start, then pages for the metrics and the controls. Today's
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

/// The pages of a run in progress. Like the Workout app, the metrics page is the default and the
/// controls (pause or resume, end, later next step) sit one swipe to the right.
private struct RunPages: View {
    let recorder: RunRecorder
    let zoneStore: WatchZoneStore
    @State private var page = Page.metrics

    private enum Page { case controls, metrics }

    var body: some View {
        TabView(selection: $page) {
            RunControlsPage(recorder: recorder)
                .tag(Page.controls)
            RunMetricsPage(recorder: recorder, zoneStore: zoneStore)
                .tag(Page.metrics)
        }
        .tabViewStyle(.page)
    }
}

/// The metrics page: elapsed time, heart rate and distance. Units follow the system's region for
/// now; the athlete's own setting comes with the zone sync (WATCH-102).
private struct RunMetricsPage: View {
    let recorder: RunRecorder
    let zoneStore: WatchZoneStore

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 2) {
                    Text(Duration.seconds(recorder.elapsed(at: context.date)),
                         format: .time(pattern: .hourMinuteSecond))
                        .font(.title2.monospacedDigit())
                        .accessibilityLabel("Elapsed time")
                    StepLine(recorder: recorder, at: context.date)
                }
            }
            ZoneBadge(bands: zoneStore.bands, hasZones: zoneStore.zones != nil, heartRate: recorder.heartRate)
            Text(recorder.heartRate.map { "\(Int($0.rounded())) bpm" } ?? "-- bpm")
                .font(.title.monospacedDigit())
                .accessibilityLabel("Heart rate")
                .accessibilityValue(recorder.heartRate.map { "\(Int($0.rounded())) beats per minute" } ?? "no reading")
            Text(Measurement(value: recorder.distanceMeters, unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(2)))))
                .font(.footnote.monospacedDigit())
                .accessibilityLabel("Distance")
            if recorder.phase == .paused {
                Text("Paused").font(.footnote).foregroundStyle(.yellow)
            }
            #if targetEnvironment(simulator)
            Text("fixes \(recorder.routePointCount), location \(recorder.locationDescription)").font(.caption2)
            Text("\(recorder.locationDiagnostics), events \(recorder.eventsWritten)").font(.system(size: 10))
            #endif
        }
    }
}

/// The controls page, one swipe to the right of the metrics. Ending asks first, since a mis-tap
/// would end and save the run.
private struct RunControlsPage: View {
    let recorder: RunRecorder
    @State private var confirmingEnd = false

    var body: some View {
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
        }
        .confirmationDialog("End this run?", isPresented: $confirmingEnd) {
            Button("End run", role: .destructive) { recorder.end() }
            Button("Keep going", role: .cancel) {}
        }
    }
}

/// The zone the current heart rate is in, from the athlete's zones sent by the iPhone (WATCH-102):
/// a coloured "Z3" with its bpm range. Says so when no zones have arrived yet, so a run without
/// them isn't mistaken for one in no zone, and when they can't be worked out.
private struct ZoneBadge: View {
    let bands: ZoneBands?
    let hasZones: Bool
    let heartRate: Double?

    var body: some View {
        if let bands {
            content(bands: bands)
        } else {
            Text(hasZones ? "Zones not set up: check TrainingApp" : "No zones yet: open TrainingApp on your iPhone")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func content(bands: ZoneBands) -> some View {
        let zone = heartRate.map { bands.zone(forHeartRate: $0) }
        let named = zone.flatMap { HeartRateZone(rawValue: $0) }
        let range = zone.flatMap { bands.range(of: $0) }
        VStack(spacing: 0) {
            Text(label(zone: zone))
                .font(.headline)
                .foregroundStyle(named?.zoneColor ?? .secondary)
            if let range {
                Text("\(Int(range.lowerBound.rounded()))-\(Int(range.upperBound.rounded()))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(zone: zone, range: range))
    }

    private func label(zone: Int?) -> String {
        switch zone {
        case nil: "Z-"
        case 0: "<Z1"
        case let zone?: "Z\(zone)"
        }
    }

    private func accessibilityLabel(zone: Int?, range: ClosedRange<Double>?) -> String {
        guard let zone else { return "No zone" }
        guard zone > 0 else { return "Below zone 1" }
        guard let range else { return "Zone \(zone)" }
        return "Zone \(zone), \(Int(range.lowerBound.rounded())) to \(Int(range.upperBound.rounded())) beats per minute"
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

/// Where the run is in a planned workout (WATCH-104): the current step and what is left of it, or
/// "Workout done" once the last step is over. Nothing in a free run. The full run screen is WATCH-105.
private struct StepLine: View {
    let recorder: RunRecorder
    let at: Date

    var body: some View {
        if let engine = recorder.stepEngine {
            VStack(spacing: 0) {
                if let current = engine.current {
                    Text("\(current.index + 1)/\(engine.steps.count)  \(WatchWorkoutSummary.stepText(current.step))")
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if let progress = recorder.stepProgress(at: at),
                       let left = WatchWorkoutSummary.remainingText(progress) {
                        Text(left).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                    } else {
                        Text("Press Lap to move on").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Workout done").font(.system(size: 12)).foregroundStyle(.green)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
