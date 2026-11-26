import CoreLocation
import Foundation
import Testing
import TrainingCore
@testable import TrainingWatchKit

private func plan(_ steps: [WorkoutStep]) -> WatchPlannedWorkout {
    WatchPlannedWorkout(id: UUID(), date: .now, name: "Test", blocks: [WorkoutBlock(steps: steps)])
}

private func time(_ seconds: TimeInterval, kind: StepKind = .work) -> WorkoutStep {
    WorkoutStep(kind: kind, goal: .time(seconds), target: .heartRateRange(140, 150))
}

private func fix(_ latitude: Double) -> CLLocation {
    CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 4), altitude: 0,
        horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: .now)
}

@MainActor
private func makeRecorder(_ backend: FakeBackend = FakeBackend()) -> (RunRecorder, FakeBackend) {
    (RunRecorder(backend: backend), backend)
}

/// A recorder with a run going, as after Start.
@MainActor
private func running(
    plan: WatchPlannedWorkout? = nil, backend: FakeBackend = FakeBackend()
) async -> (RunRecorder, FakeBackend) {
    let (recorder, backend) = makeRecorder(backend)
    await recorder.start(plan: plan)
    return (recorder, backend)
}

@MainActor
@Suite("RunRecorder phases (WATCH-113)")
struct RunRecorderPhaseTests {
    @Test("a start begins the session and the sensors and runs")
    func start() async {
        let (recorder, backend) = await running()
        #expect(recorder.phase == .running)
        #expect(backend.session.calls == ["start"])
        #expect(backend.builder.calls == ["begin"])
        #expect(backend.sensorCalls == ["start"])
    }

    @Test("a second start while one runs or starts is ignored")
    func doubleStart() async {
        let (recorder, backend) = makeRecorder()
        async let first: Void = recorder.start()
        async let second: Void = recorder.start()
        _ = await (first, second)
        #expect(backend.session.calls == ["start"])
        await recorder.start()
        #expect(backend.session.calls == ["start"])
        #expect(recorder.phase == .running)
    }

    @Test("a failed start tears down and fails, and the next run can start")
    func failedStartTeardown() async {
        let (recorder, backend) = makeRecorder()
        backend.builder.beginCollectionFails = true
        await recorder.start()
        #expect(recorder.phase == .failed("fake failure"))
        #expect(backend.session.calls == ["start", "end"])
        #expect(backend.builder.calls.contains("discard"))
        #expect(backend.sensorCalls == ["stop"])
        recorder.reset()
        #expect(recorder.phase == .idle)
        backend.builder.beginCollectionFails = false
        await recorder.start()
        #expect(recorder.phase == .running)
    }

    @Test("a failed health request fails the start before any session")
    func healthRequestFails() async {
        let (recorder, backend) = makeRecorder()
        backend.healthRequestFails = true
        await recorder.start()
        #expect(recorder.phase == .failed("fake failure"))
        #expect(backend.session.calls.isEmpty)
    }

    @Test("a session that fails during the run tears it down")
    func sessionFailure() async {
        let (recorder, backend) = await running()
        backend.session.onFailure?("sensor gone")
        await settle()
        #expect(recorder.phase == .failed("sensor gone"))
        #expect(backend.session.calls.last == "end")
        #expect(backend.sensorCalls.last == "stop")
        // The teardown's own `.ended` must not try to save the discarded workout.
        backend.session.onStateChange?(.ended)
        await settle()
        #expect(recorder.phase == .failed("sensor gone"))
        #expect(!backend.builder.calls.contains("finishWorkout"))
    }

    @Test("pause and resume go through the session and follow its state, and only in the right phase")
    func pauseAndResume() async {
        let (recorder, backend) = await running()
        recorder.resume()
        #expect(backend.session.calls == ["start"])
        recorder.pause()
        #expect(backend.session.calls == ["start", "pause"])
        backend.session.onStateChange?(.paused)
        await settle()
        #expect(recorder.phase == .paused)
        #expect(backend.sensorCalls == ["start", "pause"])
        recorder.pause()
        #expect(backend.session.calls == ["start", "pause"])
        recorder.resume()
        backend.session.onStateChange?(.running)
        await settle()
        #expect(recorder.phase == .running)
        #expect(backend.sensorCalls == ["start", "pause", "resume"])
    }

    @Test("ending while paused saves the run")
    func endWhilePaused() async {
        let (recorder, backend) = await running()
        backend.session.onStateChange?(.paused)
        await settle()
        recorder.end()
        #expect(recorder.phase == .saving)
        #expect(backend.session.calls.last == "end")
        // A late report from the session doesn't bring the controls back.
        backend.session.onStateChange?(.paused)
        await settle()
        #expect(recorder.phase == .saving)
        backend.session.onStateChange?(.ended)
        await settle()
        #expect(recorder.phase == .saved)
        #expect(backend.builder.calls == ["begin", "endCollection", "finishWorkout"])
    }

    @Test("ending leaves the running phase at once, so the controls can't be used twice (WATCH-130)")
    func endLeavesControlsAtOnce() async {
        let (recorder, backend) = await running()
        recorder.end()
        #expect(recorder.phase == .saving)
        recorder.end()
        #expect(backend.session.calls.filter { $0 == "end" }.count == 1)
        // A fix that arrives before the session reports the end is still part of the route.
        backend.sendLocations?([fix(52)])
        await settle()
        #expect(backend.builder.routePoints == 1)
        // A late state change from the session doesn't bring the controls back.
        backend.session.onStateChange?(.running)
        await settle()
        #expect(recorder.phase == .saving)
        backend.session.onStateChange?(.ended)
        await settle()
        #expect(recorder.phase == .saved)
    }

    @Test("end does nothing before a run or after it")
    func endOutsideRun() async {
        let (recorder, backend) = makeRecorder()
        recorder.end()
        #expect(backend.session.calls.isEmpty)
    }

    @Test("a failed save keeps the run, and a retry saves it without ending the collection twice")
    func failedSaveAndRetry() async {
        let (recorder, backend) = await running()
        backend.builder.finishWorkoutFailures = 1
        backend.session.onStateChange?(.ended)
        await settle()
        #expect(recorder.phase == .failed("The run couldn't be saved: fake failure"))
        #expect(recorder.canRetrySave)
        await recorder.retrySave()
        #expect(recorder.phase == .saved)
        #expect(!recorder.canRetrySave)
        #expect(backend.builder.calls.filter { $0 == "endCollection" }.count == 1)
        #expect(backend.builder.calls.filter { $0 == "finishWorkout" }.count == 2)
    }

    @Test("a retry is ignored when there is nothing to retry")
    func retryWithoutFailure() async {
        let (recorder, backend) = await running()
        await recorder.retrySave()
        #expect(recorder.phase == .running)
        #expect(!backend.builder.calls.contains("finishWorkout"))
    }

    @Test("discarding a run that couldn't be saved throws it away")
    func discardAfterFailedSave() async {
        let (recorder, backend) = await running()
        backend.builder.finishWorkoutFailures = 1
        backend.session.onStateChange?(.ended)
        await settle()
        recorder.reset()
        #expect(recorder.phase == .idle)
        #expect(backend.builder.calls.last == "discard")
        #expect(recorder.distanceMeters == 0)
    }

    @Test("reset does nothing while a run goes on")
    func resetWhileRunning() async {
        let (recorder, _) = await running()
        recorder.reset()
        #expect(recorder.phase == .running)
    }
}

@MainActor
@Suite("RunRecorder permissions and the route (WATCH-113)")
struct RunRecorderPermissionTests {
    @Test("workouts that can't be saved to Health fail the start with the way to fix it")
    func healthDenied() async {
        let (recorder, backend) = makeRecorder()
        backend.healthAllowed = false
        await recorder.start()
        guard case .failed(let message) = recorder.phase else {
            Issue.record("expected a failure, got \(recorder.phase)")
            return
        }
        #expect(message.contains("turn on Workouts"))
        #expect(backend.session.calls.isEmpty)
        recorder.reset()
        #expect(recorder.phase == .idle)
    }

    @Test("denied location still records the run, and says there is no route")
    func locationDenied() async {
        let backend = FakeBackend()
        backend.locationAllowed = false
        let (recorder, _) = await running(backend: backend)
        backend.sendLocations?([fix(52)])
        await settle()
        backend.session.onStateChange?(.ended)
        await settle()
        #expect(recorder.phase == .saved)
        #expect(recorder.routeNote?.contains("location is off") == true)
        #expect(!backend.builder.calls.contains("finishRoute"))
    }

    @Test("a run with location saves its route, and one without fixes saves none and says nothing")
    func routeSaved() async {
        let (recorder, backend) = await running()
        backend.sendLocations?([fix(52), fix(52.001)])
        await settle()
        #expect(recorder.routePointCount == 2)
        #expect(backend.builder.routePoints == 2)
        backend.session.onStateChange?(.ended)
        await settle()
        #expect(recorder.phase == .saved)
        #expect(recorder.routeNote == nil)
        #expect(backend.builder.calls.last == "finishRoute")

        let (emptyRecorder, emptyBackend) = await running()
        emptyBackend.session.onStateChange?(.ended)
        await settle()
        #expect(emptyRecorder.phase == .saved)
        #expect(emptyRecorder.routeNote == nil)
        #expect(!emptyBackend.builder.calls.contains("finishRoute"))
    }

    @Test("a route that fails to save leaves the run saved, with a note")
    func routeFails() async {
        let (recorder, backend) = await running()
        backend.builder.finishRouteFailures = 1
        backend.sendLocations?([fix(52)])
        await settle()
        backend.session.onStateChange?(.ended)
        await settle()
        #expect(recorder.phase == .saved)
        #expect(recorder.routeNote == "The route couldn't be saved.")
    }

    @Test("fixes during a pause are left out of the route")
    func noFixesWhilePaused() async {
        let (recorder, backend) = await running()
        backend.session.onStateChange?(.paused)
        await settle()
        backend.sendLocations?([fix(52)])
        await settle()
        #expect(recorder.routePointCount == 0)
        #expect(backend.builder.routePoints == 0)
    }
}

@MainActor
@Suite("RunRecorder distance and heart rate (WATCH-113)")
struct RunRecorderSensorTests {
    @Test("altitude and heart rate feed the run's stats, bad vertical accuracy is skipped, and the next run starts over (WATCH-135)")
    func runStats() async {
        let (recorder, backend) = await running()
        func fix(altitude: Double, accuracy: Double) -> CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 52, longitude: 4), altitude: altitude,
                horizontalAccuracy: 5, verticalAccuracy: accuracy, timestamp: .now)
        }
        backend.sendLocations?([fix(altitude: 10, accuracy: 5), fix(altitude: 500, accuracy: 80), fix(altitude: 20, accuracy: -1)])
        backend.builder.onHeartRate?(140)
        backend.builder.onHeartRate?(160)
        await settle()
        #expect(recorder.stats.altitude == 10)
        #expect(recorder.stats.averageHeartRate == 150)
        #expect(recorder.stats.maxHeartRate == 160)
        backend.session.onStateChange?(.ended)
        await settle()
        recorder.reset()
        #expect(recorder.stats.altitude == nil)
        #expect(recorder.stats.averageHeartRate == nil)
    }

    @Test("other collected quantities keep their statistics for the run, and the next run starts over (WATCH-135)")
    func quantities() async {
        let (recorder, backend) = await running()
        backend.builder.onQuantity?(.cadence, 170)
        backend.builder.onQuantity?(.cadence, 180)
        await settle()
        #expect(recorder.quantities[.cadence]?.value(.average) == 175)
        #expect(recorder.quantities[.cadence]?.value(.maximum) == 180)
    }

    @Test("on a real watch the distance is the builder's total and the heart rate its latest")
    func builderReadings() async {
        let (recorder, backend) = await running()
        backend.builder.onDistance?(1500)
        backend.builder.onHeartRate?(142)
        await settle()
        #expect(recorder.distanceMeters == 1500)
        #expect(recorder.heartRate == 142)
        // Locations give the route, not the distance, and no samples go to the builder.
        backend.sendLocations?([fix(52), fix(52.01)])
        await settle()
        #expect(recorder.distanceMeters == 1500)
        #expect(backend.builder.distanceSamples.isEmpty)
    }

    @Test("when the backend supplies the sensors, the distance is the sum of the fixes' steps, as samples")
    func derivedDistance() async {
        let backend = FakeBackend()
        backend.suppliesSensorReadings = true
        let (recorder, _) = await running(backend: backend)
        let a = fix(52), b = fix(52.001), c = fix(52.002)
        backend.sendLocations?([a, b])
        await settle()
        backend.sendLocations?([c])
        await settle()
        let expected = b.distance(from: a) + c.distance(from: b)
        #expect(abs(recorder.distanceMeters - expected) < 0.001)
        #expect(backend.builder.distanceSamples.count == 2)
        #expect(abs(backend.builder.distanceSamples.reduce(0, +) - expected) < 0.001)
    }

    @Test("after a pause the distance is measured from the first fix, not from before the pause")
    func pauseGap() async {
        let backend = FakeBackend()
        backend.suppliesSensorReadings = true
        let (recorder, _) = await running(backend: backend)
        let a = fix(52), b = fix(52.001), far = fix(52.5), farther = fix(52.501)
        backend.sendLocations?([a, b])
        await settle()
        backend.session.onStateChange?(.paused)
        await settle()
        recorder.resume()
        backend.session.onStateChange?(.running)
        await settle()
        backend.sendLocations?([far, farther])
        await settle()
        let expected = b.distance(from: a) + farther.distance(from: far)
        #expect(abs(recorder.distanceMeters - expected) < 0.001)
    }

    @Test("a heart rate from a supplying backend is shown and recorded, only while running")
    func suppliedHeartRate() async {
        let backend = FakeBackend()
        backend.suppliesSensorReadings = true
        let (recorder, _) = await running(backend: backend)
        backend.sendHeartRate?(150)
        await settle()
        #expect(recorder.heartRate == 150)
        #expect(backend.builder.heartRateSamples == [150])
        backend.session.onStateChange?(.paused)
        await settle()
        backend.sendHeartRate?(160)
        await settle()
        #expect(recorder.heartRate == 150)
        #expect(backend.builder.heartRateSamples == [150])
    }

    @Test("a supplying backend (the simulator) gets made-up readings of the other quantities with each heart rate (WATCH-135)")
    func suppliedQuantities() async {
        let backend = FakeBackend()
        backend.suppliesSensorReadings = true
        let (recorder, _) = await running(backend: backend)
        backend.sendHeartRate?(150)
        await settle()
        #expect(recorder.quantities[.cadence]?.value(.current) != nil)
        #expect(recorder.quantities[.runningPower]?.value(.current) != nil)
        // A real watch's recorder adds none of its own.
        let (real, realBackend) = await running()
        realBackend.builder.onHeartRate?(150)
        await settle()
        #expect(real.quantities[.cadence] == nil)
    }

    @Test("reset clears the readings of the run before")
    func resetClears() async {
        let (recorder, backend) = await running()
        backend.builder.onDistance?(800)
        backend.builder.onHeartRate?(120)
        backend.sendLocations?([fix(52)])
        await settle()
        backend.session.onStateChange?(.ended)
        await settle()
        recorder.reset()
        #expect(recorder.distanceMeters == 0)
        #expect(recorder.heartRate == nil)
        #expect(recorder.routePointCount == 0)
    }
}

@MainActor
@Suite("RunRecorder steps and alerts (WATCH-113)")
struct RunRecorderStepTests {
    @Test("a planned run is tagged with its plan and starts its first step with one alert")
    func planStart() async throws {
        let planned = plan([time(60), time(60)])
        let (recorder, backend) = await running(plan: planned)
        #expect(recorder.stepEngine?.current?.index == 0)
        #expect(backend.builder.metadata.count == 1)
        #expect(backend.builder.metadata[0][WorkoutMetadata.plannedActivityID] as? String == planned.id.uuidString)
        #expect(backend.cues == [.zoneAlert(.stepStarted)])
        #expect(backend.announcements == ["Run, 1 minute, 140 to 150 beats per minute"])
    }

    @Test("a work step is announced ahead, once, and not again as it starts; a recovery is announced as it starts")
    func announcedAhead() async {
        let (recorder, backend) = await running(plan: plan([time(60, kind: .recovery), time(60), time(60, kind: .recovery)]))
        #expect(backend.announcements.count == 1)  // the first step, as it starts
        backend.builder.elapsed = 40
        await recorder.tickSteps()
        #expect(backend.announcements.count == 1)  // 20 s left: too early
        backend.builder.elapsed = 52
        await recorder.tickSteps()
        #expect(backend.announcements.last == "Next: work for 1 minute, 140 to 150 beats per minute")
        backend.builder.elapsed = 55
        await recorder.tickSteps()
        #expect(backend.announcements.count == 2)  // not twice
        backend.builder.elapsed = 61
        await recorder.tickSteps()
        #expect(backend.announcements.count == 2)  // the work step began: already announced
        backend.builder.elapsed = 115
        await recorder.tickSteps()
        #expect(backend.announcements.count == 2)  // a recovery isn't announced ahead
        backend.builder.elapsed = 121
        await recorder.tickSteps()
        #expect(backend.announcements.last == "Recovery, 1 minute, 140 to 150 beats per minute")
    }

    @Test("the last five seconds of a step count down with one tick a second, once each, and not after the last step")
    func countdown() async {
        let (recorder, backend) = await running(plan: plan([time(60), time(60)]))
        for (elapsed, ticks) in [(54.0, 0), (55.2, 1), (55.6, 1), (56.1, 2), (57.0, 3), (58.4, 4), (59.5, 5), (59.9, 5)] {
            backend.builder.elapsed = elapsed
            await recorder.tickSteps()
            #expect(backend.ticks == ticks, "at \(elapsed)")
        }
        // The next step starts: its alert (the longer tone) is the cue, and the countdown starts anew.
        backend.builder.elapsed = 60.1
        await recorder.tickSteps()
        #expect(backend.cues.filter { $0 == .zoneAlert(.stepStarted) }.count == 2)
        backend.builder.elapsed = 115.5
        await recorder.tickSteps()
        #expect(backend.ticks == 5)  // the last step has no step after it
    }

    @Test("no countdown while paused, and the clock ticks faster only in the last seconds of a timed step")
    func countdownPausedAndInterval() async {
        let (recorder, backend) = await running(plan: plan([time(60), time(60)]))
        #expect(recorder.tickInterval == .milliseconds(500))
        backend.builder.elapsed = 56
        #expect(recorder.tickInterval == .milliseconds(200))
        recorder.pause()
        backend.session.onStateChange?(.paused)
        await settle()
        #expect(recorder.phase == .paused)
        let before = backend.ticks
        backend.builder.elapsed = 57.5
        await recorder.tickSteps()
        #expect(backend.ticks == before)
    }

    @Test("with announcing ahead off, a work step is announced as it starts")
    func notAhead() async {
        let fake = FakeBackend()
        fake.cueSettings = CueSettings(announceWorkAhead: false)
        let (recorder, backend) = await running(plan: plan([time(60, kind: .recovery), time(60)]), backend: fake)
        backend.builder.elapsed = 55
        await recorder.tickSteps()
        #expect(backend.announcements.count == 1)
        backend.builder.elapsed = 61
        await recorder.tickSteps()
        #expect(backend.announcements.count == 2)
    }

    @Test("a free run has no steps and no step alerts")
    func freeRun() async {
        let (recorder, backend) = await running()
        #expect(recorder.stepEngine == nil)
        #expect(backend.cues.isEmpty)
        #expect(recorder.stepProgress() == nil)
    }

    @Test("steps passed in one gap each get a segment, but the new step's alert plays once")
    func severalStepsInOneGap() async {
        let (recorder, backend) = await running(plan: plan([time(10), time(10), time(10), time(10)]))
        backend.builder.elapsed = 25
        await recorder.tickSteps()
        let segments = backend.builder.events.filter { $0.kind == .segment }
        #expect(segments.count == 2)
        #expect(segments.compactMap { $0.metadata?[WorkoutMetadata.stepIndex] as? Int } == [0, 1])
        #expect(recorder.stepEngine?.current?.index == 2)
        // The first step's alert, then one for the step the run is in, not one for each passed.
        #expect(backend.cues.filter { $0 == .zoneAlert(.stepStarted) }.count == 2)
        // One announcement for the first step and one for the step the run is in.
        #expect(backend.announcements.count == 2)
        #expect(!backend.cues.contains(.goalReached))
    }

    @Test("the segments end where the engine says, so a step of 10 s is 10 s")
    func segmentIntervals() async {
        let (recorder, backend) = await running(plan: plan([time(10), time(10), time(10)]))
        // The run began 25 s ago.
        recorder.stepStartDate = .now.addingTimeInterval(-25)
        backend.builder.elapsed = 25
        await recorder.tickSteps()
        let segments = backend.builder.events.filter { $0.kind == .segment }
        #expect(segments.count == 2)
        for segment in segments { #expect(abs(segment.end.timeIntervalSince(segment.start) - 10) < 0.5) }
    }

    @Test("after the last step there is a different tap and no more alerts, even for heart rates far off")
    func afterLastStep() async {
        let (recorder, backend) = await running(plan: plan([time(10)]))
        backend.builder.elapsed = 12
        await recorder.tickSteps()
        #expect(recorder.stepEngine?.isFinished == true)
        #expect(backend.cues == [.zoneAlert(.stepStarted), .goalReached])
        #expect(backend.cancelledCues == 1)
        for second in 0..<30 {
            backend.builder.elapsed = 20 + Double(second)
            recorder.heartRateArrived(190)
        }
        #expect(backend.cues.count == 2)
        // Ticks after the end write nothing more.
        let events = backend.builder.events.count
        await recorder.tickSteps()
        #expect(backend.builder.events.count == events)
    }

    @Test("the lap button in a planned run ends the step as a lap; right after a step began it is ignored")
    func lapInPlan() async {
        let (recorder, backend) = await running(plan: plan([time(600), time(600)]))
        await recorder.lap()
        #expect(backend.builder.events.isEmpty)
        recorder.stepStartDate = .now.addingTimeInterval(-5)
        backend.builder.elapsed = 5
        await recorder.lap()
        #expect(backend.builder.events.map(\.kind) == [.segment, .lap])
        #expect(backend.builder.events[0].metadata?[WorkoutMetadata.stepEnd] as? String == "lap")
        #expect(recorder.stepEngine?.current?.index == 1)
    }

    @Test("the lap button in a free run marks a lap and taps once")
    func lapInFreeRun() async {
        let (recorder, backend) = await running()
        await recorder.lap()
        #expect(backend.builder.events.map(\.kind) == [.lap])
        #expect(backend.cues == [.lapMarked])
    }

    @Test("ending in the middle of a step writes that step's segment once, even when the save is retried")
    func endMidStep() async {
        let (recorder, backend) = await running(plan: plan([time(600)]))
        backend.builder.elapsed = 30
        backend.builder.finishWorkoutFailures = 1
        backend.session.onStateChange?(.ended)
        await settle()
        #expect(recorder.phase == .failed("The run couldn't be saved: fake failure"))
        await recorder.retrySave()
        #expect(recorder.phase == .saved)
        let segments = backend.builder.events.filter { $0.kind == .segment }
        #expect(segments.count == 1)
        #expect(segments[0].metadata?[WorkoutMetadata.stepEnd] as? String == "workoutEnded")
    }

    @Test("events that fail to write are kept and written with the next batch")
    func eventsRetried() async {
        let (recorder, backend) = await running(plan: plan([time(10), time(10), time(10)]))
        backend.builder.addEventsFailures = 1
        backend.builder.elapsed = 12
        await recorder.tickSteps()
        #expect(backend.builder.events.isEmpty)
        #expect(recorder.pendingEvents.count == 1)
        backend.builder.elapsed = 24
        await recorder.tickSteps()
        #expect(backend.builder.events.count == 2)
        #expect(recorder.pendingEvents.isEmpty)
        #expect(recorder.eventsWritten == 2)
    }

    @Test("every pause resets the alert engine: a reading out of the target right after a resume stays quiet")
    func pauseResetsAlertEngine() async {
        func alertsAfterReadings(pausing: Bool) async -> [RunCue] {
            let (recorder, backend) = await running(plan: plan([time(600)]))
            backend.builder.elapsed = 100
            if pausing {
                backend.session.onStateChange?(.paused)
                await settle()
                backend.session.onStateChange?(.running)
                await settle()
            }
            let before = backend.cues.count
            for second in 0..<3 {
                backend.builder.elapsed = 100 + Double(second)
                recorder.heartRateArrived(158)
            }
            return Array(backend.cues.dropFirst(before))
        }
        // The same readings alert without a pause and don't after one: the hold after a resume.
        #expect(await alertsAfterReadings(pausing: false).isEmpty == false)
        #expect(await alertsAfterReadings(pausing: true).isEmpty)
    }

    @Test("a zone target is turned into bpm with the athlete's zones, also when they arrive mid-step")
    func zoneTarget() async throws {
        let zones = WatchZones(settings: .init(effectiveDate: .distantPast, restingHeartRateBPM: 55, maxHeartRateBPM: 190))
        let bands = try #require(ZoneBands(zones: zones))
        let zone2 = try #require(bands.range(of: 2))
        let step = WorkoutStep(kind: .work, goal: .time(600), target: .heartRateZone(2))
        let (recorder, backend) = await running(plan: plan([step]))
        let store = WatchZoneStore(cache: WatchZonesCache(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        recorder.zoneStore = store
        // No zones yet: nothing to alert against.
        for second in 0..<5 {
            backend.builder.elapsed = 100 + Double(second)
            recorder.heartRateArrived(zone2.upperBound + 15)
        }
        #expect(backend.cues == [.zoneAlert(.stepStarted)])
        store.update(zones, persist: false)
        for second in 5..<15 {
            backend.builder.elapsed = 100 + Double(second)
            recorder.heartRateArrived(zone2.upperBound + 15)
        }
        #expect(backend.cues.count > 1)
    }

    @Test("the time in the current zone, in total and since entering it, needs a reading and zones (WATCH-135)")
    func currentZoneTime() async throws {
        let zones = WatchZones(settings: .init(effectiveDate: .distantPast, restingHeartRateBPM: 55, maxHeartRateBPM: 190))
        let bands = try #require(ZoneBands(zones: zones))
        let zone2 = try #require(bands.range(of: 2)), zone3 = try #require(bands.range(of: 3))
        let (recorder, backend) = await running()
        #expect(recorder.secondsInCurrentZone == nil)
        let store = WatchZoneStore(cache: WatchZonesCache(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        recorder.zoneStore = store
        backend.builder.elapsed = 100
        recorder.heartRateArrived(zone2.lowerBound + 1)
        // Zones haven't arrived: nothing to say.
        #expect(recorder.secondsInCurrentZone == nil)
        store.update(zones, persist: false)
        for second in 101...103 {
            backend.builder.elapsed = Double(second)
            recorder.heartRateArrived(zone2.lowerBound + 1)
        }
        backend.builder.elapsed = 105
        #expect(recorder.secondsInCurrentZone == 2)
        #expect(recorder.secondsSinceEnteringZone == 4)
        backend.builder.elapsed = 106
        recorder.heartRateArrived(zone3.lowerBound + 1)
        backend.builder.elapsed = 108
        #expect(recorder.secondsInCurrentZone == 0)
        #expect(recorder.secondsSinceEnteringZone == 2)
    }

    @Test("the time in each zone follows the heart-rate readings on the run clock, and nothing is counted without zones (WATCH-132)")
    func zoneTime() async throws {
        let zones = WatchZones(settings: .init(effectiveDate: .distantPast, restingHeartRateBPM: 55, maxHeartRateBPM: 190))
        let bands = try #require(ZoneBands(zones: zones))
        let zone2 = try #require(bands.range(of: 2))
        let zone4 = try #require(bands.range(of: 4))
        let (recorder, backend) = await running()
        // No zones yet: nothing to count.
        backend.builder.elapsed = 100
        recorder.heartRateArrived(zone2.lowerBound + 1)
        #expect(recorder.zoneTimeFractions == nil)
        let store = WatchZoneStore(cache: WatchZonesCache(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        store.update(zones, persist: false)
        recorder.zoneStore = store
        for (elapsed, bpm) in [(110.0, zone2.lowerBound + 1), (114, zone2.lowerBound + 1), (120, zone4.lowerBound + 1), (124, zone4.lowerBound + 1)] {
            backend.builder.elapsed = elapsed
            recorder.heartRateArrived(bpm)
        }
        // Zone 2 held 110 to 120 (10 s), zone 4 from 120 to 124 (4 s).
        let fractions = try #require(recorder.zoneTimeFractions)
        #expect(abs(fractions[2] - 10.0 / 14) < 0.001)
        #expect(abs(fractions[4] - 4.0 / 14) < 0.001)
    }

    @Test("a second retry while one is saving does nothing")
    func doubleRetry() async {
        let (recorder, backend) = await running()
        backend.builder.finishWorkoutFailures = 1
        backend.session.onStateChange?(.ended)
        await settle()
        async let first: Void = recorder.retrySave()
        async let second: Void = recorder.retrySave()
        _ = await (first, second)
        #expect(recorder.phase == .saved)
        #expect(backend.builder.calls.filter { $0 == "finishWorkout" }.count == 2)
    }

    @Test("heart rates only alert while running")
    func noAlertsWhilePaused() async {
        let (recorder, backend) = await running(plan: plan([time(600)]))
        backend.session.onStateChange?(.paused)
        await settle()
        let before = backend.cues.count
        for second in 0..<10 {
            backend.builder.elapsed = 100 + Double(second)
            recorder.heartRateArrived(190)
        }
        #expect(backend.cues.count == before)
    }
}

@MainActor
@Suite("RunRecorder battery (WATCH-113)")
struct RunRecorderBatteryTests {
    @Test("a low battery shows a warning and taps the wrist; dismissing takes it away")
    func warning() async {
        let backend = FakeBackend()
        backend.batteryLevel = 0.03
        let (recorder, _) = await running(plan: plan([time(3600)]), backend: backend)
        backend.builder.elapsed = 10
        recorder.checkBattery()
        #expect(recorder.batteryWarning != nil)
        #expect(backend.cues.contains { if case .batteryWarning = $0 { true } else { false } })
        recorder.dismissBatteryWarning()
        #expect(recorder.batteryWarning == nil)
    }

    @Test("a healthy battery warns of nothing")
    func noWarning() async {
        let (recorder, backend) = await running()
        backend.builder.elapsed = 10
        recorder.checkBattery()
        #expect(recorder.batteryWarning == nil)
        #expect(recorder.batteryReadings.count == 1)
    }

    @Test("a warning goes when the run ends")
    func warningEnds() async {
        let backend = FakeBackend()
        backend.batteryLevel = 0.03
        let (recorder, _) = await running(backend: backend)
        backend.builder.elapsed = 10
        recorder.checkBattery()
        backend.session.onStateChange?(.ended)
        await settle()
        #expect(recorder.batteryWarning == nil)
    }
}

@MainActor
@Suite("RunRecorder pace")
struct RunRecorderPaceTests {
    /// Feeds the builder's total distance at 3 m/s, one reading a second, for `seconds`.
    private func feed(_ backend: FakeBackend, seconds: Int) async {
        for second in 1...seconds {
            backend.builder.elapsed = TimeInterval(second)
            backend.builder.onDistance?(Double(second) * 3)
            await settle()
        }
    }

    @Test("the pace follows the builder's distance and elapsed time")
    func paceFromDistance() async throws {
        let (recorder, backend) = await running()
        #expect(recorder.currentSecondsPerMeter() == nil)
        #expect(recorder.averageSecondsPerMeter == nil)
        await feed(backend, seconds: 30)
        let current = try #require(recorder.currentSecondsPerMeter())
        let average = try #require(recorder.averageSecondsPerMeter)
        #expect(abs(current - 1.0 / 3) < 0.0001)
        #expect(abs(average - 1.0 / 3) < 0.0001)
    }

    @Test("reset forgets the pace of the run before")
    func resetForgets() async {
        let (recorder, backend) = await running()
        await feed(backend, seconds: 30)
        backend.session.onStateChange?(.ended)
        await settle()
        recorder.reset()
        #expect(recorder.currentSecondsPerMeter() == nil)
        #expect(recorder.averageSecondsPerMeter == nil)
    }

    @Test("a distance reading that arrives after the run is released starts no pace")
    func lateReading() async {
        let (recorder, backend) = await running()
        await feed(backend, seconds: 30)
        backend.session.onStateChange?(.ended)
        await settle()
        recorder.reset()
        // With no builder `elapsed()` would be 0 and the window would take the reading as a new run.
        backend.builder.onDistance?(9999)
        await settle()
        #expect(recorder.averageSecondsPerMeter == nil)
        #expect(recorder.currentSecondsPerMeter() == nil)
    }
}

