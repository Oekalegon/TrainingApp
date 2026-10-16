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

        #expect(editor.shown[.monday] == [.afternoonEvening])
        #expect(profile.availability[.monday] == [.afternoonEvening])
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
