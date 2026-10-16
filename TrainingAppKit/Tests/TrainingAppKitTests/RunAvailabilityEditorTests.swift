import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// MVP5-105: the editor shows a change at once and reconciles it with the outcome of the save.
@MainActor
@Suite("RunAvailabilityEditor")
struct RunAvailabilityEditorTests {
    /// A stand-in for the profile whose saves can be failed or held back.
    @MainActor
    final class Profile {
        var availability = RunAvailability()
        var failing: Set<Int> = []
        var saveCount = 0
        var gates: [Int: CheckedContinuation<Void, Never>] = [:]
        var holds: Set<Int> = []

        func save(_ new: RunAvailability) async -> Bool {
            saveCount += 1
            let number = saveCount
            if holds.contains(number) {
                await withCheckedContinuation { gates[number] = $0 }
            }
            if failing.contains(number) { return false }
            availability = new
            return true
        }
    }

    private func makeEditor(_ profile: Profile) -> RunAvailabilityEditor {
        RunAvailabilityEditor(saved: { profile.availability }, save: { await profile.save($0) })
    }

    @Test("a toggle is saved and shown")
    func saves() async {
        let profile = Profile()
        let editor = makeEditor(profile)

        await editor.toggleDay(.monday)
        await editor.toggleSlot(.morning, on: .monday)
        await editor.toggleSlot(.afternoon, on: .monday)

        #expect(editor.shown[.monday] == [.evening])
        #expect(profile.availability[.monday] == [.evening])

        // Switching the last part off clears the day.
        await editor.toggleSlot(.evening, on: .monday)
        #expect(!editor.shown.isAvailable(on: .monday))
        #expect(profile.availability == RunAvailability())
        #expect(!editor.didFail)
    }

    @Test("a failed save reverts to what is saved and reports it")
    func failedLatestSave() async {
        let profile = Profile()
        profile.failing = [1]
        let editor = makeEditor(profile)

        await editor.toggleDay(.friday)

        #expect(editor.didFail)
        #expect(editor.shown == RunAvailability())
        #expect(profile.availability == RunAvailability())
    }

    @Test("runs per day are saved, and a failed save reverts them")
    func runs() async {
        let profile = Profile()
        let editor = makeEditor(profile)
        await editor.toggleDay(.saturday)

        await editor.setRuns(2, on: .saturday)
        #expect(editor.shown.runs(on: .saturday) == 2)
        #expect(profile.availability.runs(on: .saturday) == 2)

        profile.failing = [3]
        await editor.setRuns(3, on: .saturday)
        #expect(editor.didFail)
        #expect(editor.shown.runs(on: .saturday) == 2)
    }

    @Test("a failed part toggle reverts to the saved parts")
    func failedSlotToggle() async {
        let profile = Profile()
        let editor = makeEditor(profile)
        await editor.toggleDay(.monday)
        profile.failing = [2]

        await editor.toggleSlot(.morning, on: .monday)

        #expect(editor.didFail)
        #expect(editor.shown[.monday] == [.morning, .afternoon, .evening])
    }

    @Test("quick toggles compose, and a failed earlier save is covered by the later one")
    func quickTogglesCompose() async {
        let profile = Profile()
        profile.holds = [1]
        profile.failing = [1]
        let editor = makeEditor(profile)

        let first = Task { await editor.toggleDay(.monday) }
        await Task.yield()
        // The first save is still outstanding: its change is shown, and the second builds on it.
        #expect(editor.shown.isAvailable(on: .monday))
        await editor.toggleDay(.tuesday)
        #expect(editor.shown.isAvailable(on: .monday) && editor.shown.isAvailable(on: .tuesday))

        profile.gates[1]?.resume()
        await first.value

        #expect(editor.didFail)
        #expect(profile.availability.isAvailable(on: .monday))
        #expect(profile.availability.isAvailable(on: .tuesday))
        #expect(editor.shown == profile.availability)
    }
}

/// MVP5-112: run types follow the same save rules as the other edits.
@MainActor
@Suite("RunAvailabilityEditor run types")
struct RunAvailabilityEditorRunTypeTests {
    private func makeEditor(_ profile: RunAvailabilityEditorTests.Profile) -> RunAvailabilityEditor {
        RunAvailabilityEditor(saved: { profile.availability }, save: { await profile.save($0) })
    }

    @Test("a failed run type toggle or clear reverts to the saved types and reports it")
    func failedRunTypes() async {
        let profile = RunAvailabilityEditorTests.Profile()
        let editor = makeEditor(profile)
        await editor.toggleDay(.friday)
        await editor.toggleRunType(.long, on: .friday)
        profile.failing = [3]

        await editor.toggleRunType(.interval, on: .friday)
        #expect(editor.didFail)
        #expect(editor.shown.dayRunTypes[.friday] == [.long])

        editor.didFail = false
        profile.failing = [4]
        await editor.clearRunTypes(on: .friday)
        #expect(editor.didFail)
        #expect(editor.shown.dayRunTypes[.friday] == [.long])
    }

    @Test("run types are kept when a day is switched off and on again")
    func keptAcrossDayToggle() async {
        let profile = RunAvailabilityEditorTests.Profile()
        let editor = makeEditor(profile)
        await editor.toggleDay(.friday)
        await editor.toggleRunType(.long, on: .friday)
        await editor.toggleDay(.friday)
        #expect(editor.shown.summary(on: .friday) == "Off")
        await editor.toggleDay(.friday)
        #expect(editor.shown.dayRunTypes[.friday] == [.long])
    }
}
