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
}
