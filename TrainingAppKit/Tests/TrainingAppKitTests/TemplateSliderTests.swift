import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// The planned-workout sheet's sliders on every built-in template (MVP2-106): each has a step, the
/// default and both ends of the range sit on its notches, so the thumb starts where the template says
/// and a value can't land between two figures the athlete would type.
@Suite("Template parameter sliders (MVP2-106)")
struct TemplateSliderTests {
    @Test("every built-in parameter's default and range ends are on a notch of its slider")
    func builtInParametersAreOnTheirNotches() {
        var problems: [String] = []
        for template in BuiltInWorkoutTemplates.all {
            for parameter in template.parameters {
                let range = parameter.sliderRange
                let step = parameter.sliderStep
                func onNotch(_ value: Double) -> Bool {
                    let notches = (value - range.lowerBound) / step
                    return abs(notches - notches.rounded()) < 1e-9
                }
                if !range.contains(parameter.defaultValue) {
                    problems.append("\(template.name) / \(parameter.key): default \(parameter.defaultValue) outside \(range)")
                }
                if !onNotch(parameter.defaultValue) {
                    problems.append("\(template.name) / \(parameter.key): default \(parameter.defaultValue) off the \(step) grid from \(range.lowerBound)")
                }
                if !onNotch(range.upperBound) {
                    problems.append("\(template.name) / \(parameter.key): upper bound \(range.upperBound) off the \(step) grid from \(range.lowerBound)")
                }
                if range.upperBound - range.lowerBound < step {
                    problems.append("\(template.name) / \(parameter.key): range \(range) narrower than its step \(step)")
                }
            }
        }
        #expect(BuiltInWorkoutTemplates.all.flatMap(\.parameters).count > 20)
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    @Test("steps follow the unit and the length of the range")
    func steps() {
        func parameter(_ unit: ParameterUnit, _ range: ClosedRange<Double>) -> WorkoutTemplateParameter {
            WorkoutTemplateParameter(key: "p", name: "P", unit: unit, defaultValue: range.lowerBound, range: range)
        }
        #expect(parameter(.minutes, 30...120).sliderStep == 5)
        #expect(parameter(.minutes, 180...300).sliderStep == 5)
        #expect(parameter(.minutes, 180...900).sliderStep == 15)
        #expect(parameter(.minutes, 600...2400).sliderStep == 60)
        #expect(parameter(.meters, 200...800).sliderStep == 50)
        #expect(parameter(.meters, 2_000...30_000).sliderStep == 100)
        #expect(parameter(.count, 3...12).sliderStep == 1)
    }

    @Test("a value is moved to the nearest notch, counted from the lower bound, and kept in the range")
    func snapping() {
        let rest = WorkoutTemplateParameter(key: "rest", name: "Rest", unit: .minutes, defaultValue: 90, range: 60...180)
        #expect(rest.snapped(94.3) == 95)
        #expect(rest.snapped(92.4) == 90)
        #expect(rest.snapped(10) == 60)
        #expect(rest.snapped(500) == 180)
        // Counted from the lower bound, so a range that doesn't start on a multiple of the step keeps its own notches.
        let offset = WorkoutTemplateParameter(key: "d", name: "D", unit: .meters, defaultValue: 225, range: 225...825)
        #expect(offset.snapped(262) == 275)
        let reps = WorkoutTemplateParameter(key: "reps", name: "Reps", unit: .count, defaultValue: 6, range: 4...10)
        #expect(reps.snapped(7.6) == 8)
    }

    @Test("a parameter with no range gets half to double its default, and at least a band of one")
    func rangeFallback() {
        let none = WorkoutTemplateParameter(key: "p", name: "P", unit: .count, defaultValue: 8)
        #expect(none.sliderRange == 4...16)
        let zero = WorkoutTemplateParameter(key: "p", name: "P", unit: .count, defaultValue: 0)
        #expect(zero.sliderRange == 0...1)
    }

    // MARK: The athlete's own templates

    private func custom(_ unit: ParameterUnit, _ range: ClosedRange<Double>, default value: Double) -> WorkoutTemplateParameter {
        WorkoutTemplateParameter(key: "p", name: "P", unit: unit, defaultValue: value, range: range)
    }

    /// Whether `value` is a notch of the parameter's slider, counted from its lower bound.
    private func onNotch(_ value: Double, _ parameter: WorkoutTemplateParameter) -> Bool {
        let notches = (value - parameter.sliderRange.lowerBound) / parameter.sliderStep
        return abs(notches - notches.rounded()) < 1e-9
    }

    @Test("a custom duration range that isn't on whole minutes can still reach its maximum")
    func oddMinuteRange() {
        // 7.5 to 20 minutes with a 10 minute default: a whole-minute step from 7:30 would stop at 19:30.
        let parameter = custom(.minutes, 450...1200, default: 600)

        #expect(onNotch(parameter.sliderRange.upperBound, parameter))
        #expect(onNotch(parameter.defaultValue, parameter))
        #expect(parameter.sliderStep <= 60)
        #expect(parameter.snapped(1200) == 1200)
    }

    @Test("a range in miles, held in metres, reaches its maximum and starts within half a notch of its default")
    func imperialDistanceRange() {
        let mile = 1609.344
        let parameter = custom(.meters, 3 * mile...13 * mile, default: 8 * mile)

        #expect(onNotch(parameter.sliderRange.upperBound, parameter))
        #expect(parameter.sliderStep <= 100)
        #expect(abs(parameter.snapped(parameter.defaultValue) - parameter.defaultValue) <= parameter.sliderStep / 2 + 1e-9)
        #expect(parameter.snapped(13 * mile) == 13 * mile)
    }

    @Test("a step never exceeds the one its range length allows, and finer ones are used only when needed")
    func stepStaysCoarseWhenItCan() {
        #expect(custom(.minutes, 30...120, default: 60).sliderStep == 5)
        #expect(custom(.minutes, 600...2400, default: 1200).sliderStep == 60)
        // A default two seconds off the 5 s grid needs the 1 s step; one on it keeps 5 s.
        #expect(custom(.minutes, 60...300, default: 132).sliderStep == 1)
        #expect(custom(.minutes, 60...300, default: 120).sliderStep == 5)
    }

    @Test("a fractional count range is divided so its maximum is a notch")
    func fractionalCountRange() {
        let parameter = custom(.count, 2.5...10, default: 5)
        #expect(onNotch(10, parameter))
        #expect(parameter.sliderStep > 0)
    }

    @Test("a new plan's sliders start on a notch, and an edited plan keeps what it was made with")
    @MainActor
    func seedingSnapsOnlyNewPlans() throws {
        let parameter = WorkoutTemplateParameter(
            key: "duration", name: "Duration", unit: .minutes, defaultValue: 600, range: 450...1200
        )
        // No step puts both ends of this range in miles' metres on a notch, so the default ends up off one.
        let mile = 1609.344
        let off = WorkoutTemplateParameter(
            key: "rest", name: "Rest", unit: .meters, defaultValue: 8 * mile, range: 3 * mile...13 * mile
        )
        let template = WorkoutTemplate(
            name: "Mine", sport: .running, parameters: [parameter, off],
            blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.parameter("duration")))])]
        )
        let store = InMemoryStore()
        let model = TrainingModel(
            stores: StoreSet(
                activityStore: store, planStore: store, workoutStore: store,
                cycleStore: store, raceStore: store, athleteStore: store
            ),
            athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        )
        let viewModel = PlannedWorkoutSheetViewModel(model: model, templates: [template], scheduler: nil)

        viewModel.selectedTemplate = template

        for parameter in template.parameters {
            let seeded = try #require(viewModel.parameterValues[parameter.key])
            #expect(seeded == parameter.snapped(parameter.defaultValue))
        }
        // The default 12874.752 m is not on a notch; the new plan starts on the nearest one.
        #expect(viewModel.parameterValues["rest"] != off.defaultValue)
        #expect(abs((viewModel.parameterValues["rest"] ?? 0) - off.defaultValue) <= off.sliderStep / 2 + 1e-9)
    }
}
