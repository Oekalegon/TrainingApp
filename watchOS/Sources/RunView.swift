import SwiftUI
import TrainingCore
import TrainingWatchKit

/// The recording screen of WATCH-101: start, then pages for the metrics and the controls.
struct RunView: View {
    let recorder: RunRecorder
    let zoneStore: WatchZoneStore
    let planStore: WatchPlanStore

    var body: some View {
        content
            #if targetEnvironment(simulator)
            // `-autostart` lets a script start a run without tapping (simulator only).
            .task {
                if CommandLine.arguments.contains("-autostart"), recorder.phase == .idle {
                    await recorder.start()
                }
                // `-autopause <after>,<for>` pauses the run after that many seconds for that many
                // seconds, for headless testing of pause and resume.
                if let index = CommandLine.arguments.firstIndex(of: "-autopause"),
                   index + 1 < CommandLine.arguments.count {
                    let parts = CommandLine.arguments[index + 1].split(separator: ",").compactMap { Double($0) }
                    if parts.count == 2 {
                        Task {
                            try? await Task.sleep(for: .seconds(parts[0]))
                            recorder.pause()
                            try? await Task.sleep(for: .seconds(parts[1]))
                            recorder.resume()
                        }
                    }
                }
                // `-autoend <seconds>` ends the run after that long, for headless testing.
                if let index = CommandLine.arguments.firstIndex(of: "-autoend"),
                   index + 1 < CommandLine.arguments.count,
                   let seconds = Double(CommandLine.arguments[index + 1]) {
                    try? await Task.sleep(for: .seconds(seconds))
                    recorder.end()
                }
            }
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
                    TodayWorkouts(planStore: planStore)
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
                Text(Duration.seconds(recorder.elapsed(at: context.date)),
                     format: .time(pattern: .hourMinuteSecond))
                    .font(.title2.monospacedDigit())
                    .accessibilityLabel("Elapsed time")
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
            Text(recorder.locationDiagnostics).font(.system(size: 10))
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
/// "the phone hasn't said". Starting one with its steps comes with the step engine (WATCH-104), so
/// for now it shows what is planned while "Start run" records a free run. The minute-by-minute
/// timeline moves "today" on at midnight if the app stays open.
private struct TodayWorkouts: View {
    let planStore: WatchPlanStore

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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(planned.name).font(.headline)
                            ForEach(Array(WatchWorkoutSummary.lines(for: planned.blocks).enumerated()), id: \.offset) { _, line in
                                Text(line).font(.system(size: 12))
                            }
                        }
                        .accessibilityElement(children: .combine)
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
