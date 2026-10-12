import Foundation
import TrainingCore

/// What the athlete did in one step, as the step cards write it (MVP2-146): the Watch's own figures
/// for that step. Distance and pace are missing when the step recorded no distance, or the app may
/// not read it (see `HealthKitAuthorization.readTypes`).
public struct WorkoutStepActual: Equatable, Sendable {
    /// Time spent in the step, e.g. "7:52" or "1:05:22".
    public let duration: String
    /// Distance covered, e.g. "802 m" or "9.99 km".
    public let distance: String?
    /// Average heart rate in beats per minute, e.g. "152".
    public let averageHeartRate: String?
    /// Average pace, e.g. "6:32 /km".
    public let averagePace: String?
    /// Whether the Watch counted the step's goal as met; `nil` when it didn't say.
    public let wasGoalMet: Bool?
}

/// One step as the step cards show it (MVP2-143), after how the Fitness app lists a structured
/// workout: a role, what ends the step, and the intensity it aims for.
///
/// Built from resolved values (``WorkoutBlockCard/cards(for:)``), so the template detail, the editor and
/// the planned-workout sheet and the linked activity (MVP2-144) all say a step the same way.
public struct WorkoutStepCard: Identifiable, Equatable, Sendable {
    /// What ends a step.
    public enum End: Equatable, Sendable {
        /// A duration.
        case time
        /// A distance.
        case distance
        /// The athlete ends it.
        case open
    }

    /// The step's position among all of the workout's steps.
    public let id: Int
    /// The role the step plays.
    public let kind: StepKind
    /// The role's name, e.g. "Warm-up".
    public let title: String
    /// What ends the step, e.g. "5:00", "400 m" or "Open".
    public let detail: String
    /// The kind of end ``detail`` describes; it decides the icon's colour.
    public let end: End
    /// The intensity the step aims for, e.g. "HR Zone 2"; `nil` without a target.
    public let target: String?
    /// The SF Symbol shown before ``target``: a heart for heart rate, a shoe for pace; `nil` without a
    /// target.
    public let targetSymbol: String?
    /// The name of the template parameter that sets what ends the step (its duration or distance), shown
    /// in place of ``detail``'s value so the card says where the template can be tuned; `nil` for a
    /// fixed value.
    public var parameterName: String? = nil
    /// What the athlete did in this step, when the activity recorded it (MVP2-146); `nil` otherwise.
    public var actual: WorkoutStepActual? = nil
    /// `true` for a planned step with no recorded step in an activity that has them: skipped, or the
    /// workout ended before it.
    public var isNotRecorded = false
    /// The recorded step's position among the activity's steps in the order performed
    /// (``Activity/orderedSteps``), which is also its span's id on the activity charts; `nil` without
    /// one. What a tap on the card highlights.
    public var recordedStepID: Int? = nil
}

/// Steps that repeat together, as one card in the step list. A block that runs once shows its steps as
/// separate cards; one that repeats is a "Repeat N" card holding them.
public struct WorkoutBlockCard: Identifiable, Equatable, Sendable {
    /// The block's position in the workout.
    public let id: Int
    /// How many times the steps repeat.
    public let repetitions: Int
    /// The steps of one repetition.
    public var steps: [WorkoutStepCard]
    /// The name of the template parameter that sets the repeat count; `nil` for a fixed count.
    public var repetitionsParameterName: String? = nil
    /// Which repetition (from 1) this card is, when a repeating block is shown one card per repetition
    /// so each can carry its own recorded figures (MVP2-146); `nil` for a block shown once.
    public var repetitionNumber: Int? = nil

    /// Whether the block is drawn as a "Repeat" card: it repeats, or holds several steps that belong
    /// together. A single step run once is a plain step card.
    public var isGroup: Bool { repetitions > 1 || steps.count > 1 }

    /// The cards for `blocks`, numbering steps across the whole workout.
    ///
    /// - Parameter blocks: A workout's blocks, e.g. from ``WorkoutTemplate/instantiate(name:values:)``.
    /// - Parameter distanceSystem: How distances are written; defaults to the device's measurement
    ///   system, as for default titles (``WorkoutLibraryViewModel/distanceSystem``).
    public static func cards(
        for blocks: [WorkoutBlock], distanceSystem: DistanceSystem = .deviceDefault
    ) -> [WorkoutBlockCard] {
        var stepNumber = 0
        return blocks.enumerated().map { index, block in
            let steps = block.steps.map { step in
                defer { stepNumber += 1 }
                return WorkoutStepCard(
                    id: stepNumber, kind: step.kind, title: step.kind.displayName,
                    detail: goalText(step.goal, distanceSystem: distanceSystem), end: end(of: step.goal),
                    target: step.target.map(targetText), targetSymbol: step.target.map(targetSymbol)
                )
            }
            return WorkoutBlockCard(id: index, repetitions: block.repetitions, steps: steps)
        }
    }

    /// The cards for `blocks` with what the athlete did in each step (MVP2-146): a repeating block is
    /// shown one card per repetition ("Repeat 2 of 5"), since each repetition has its own figures.
    ///
    /// - Parameters:
    ///   - blocks: A workout's blocks.
    ///   - actuals: The recorded step for each planned step in the order they are performed with
    ///     repetitions expanded, from ``ActivityStepAligner/align(_:with:)``; `nil` elements are planned
    ///     steps with no recorded step.
    ///   - recordedIDs: Each recorded step's position in the activity's ordered steps, to give the cards
    ///     the ids a tap highlights on the charts; empty leaves them without.
    ///   - distanceSystem: How distances and paces are written; defaults to the device's.
    public static func cards(
        for blocks: [WorkoutBlock], actuals: [ActivityStep?], recordedIDs: [ActivityStep: Int] = [:],
        distanceSystem: DistanceSystem = .deviceDefault
    ) -> [WorkoutBlockCard] {
        var index = 0
        var result: [WorkoutBlockCard] = []
        for (blockIndex, block) in blocks.enumerated() {
            let repetitions = max(block.repetitions, 1)
            for repetition in 1...repetitions {
                let steps = block.steps.map { step -> WorkoutStepCard in
                    defer { index += 1 }
                    var card = WorkoutStepCard(
                        id: index, kind: step.kind, title: step.kind.displayName,
                        detail: goalText(step.goal, distanceSystem: distanceSystem), end: end(of: step.goal),
                        target: step.target.map(targetText), targetSymbol: step.target.map(targetSymbol)
                    )
                    if index < actuals.count, let recorded = actuals[index] {
                        card.actual = actual(for: recorded, distanceSystem: distanceSystem)
                        card.recordedStepID = recordedIDs[recorded]
                    } else {
                        card.isNotRecorded = true
                    }
                    return card
                }
                var card = WorkoutBlockCard(
                    id: blockIndex * 10_000 + repetition, repetitions: repetitions, steps: steps
                )
                if repetitions > 1 { card.repetitionNumber = repetition }
                result.append(card)
            }
        }
        return result
    }

    /// What the athlete did in `step`, written as the cards show it.
    static func actual(for step: ActivityStep, distanceSystem: DistanceSystem = .deviceDefault) -> WorkoutStepActual {
        WorkoutStepActual(
            duration: durationText(step.duration),
            distance: step.distanceMeters.map { actualDistanceText($0, in: distanceSystem) },
            averageHeartRate: step.averageHeartRateBPM.map { Int($0.rounded()).formatted() },
            averagePace: step.averagePaceSecondsPerKilometer.map { paceText(secondsPerKilometer: $0, in: distanceSystem) },
            wasGoalMet: step.wasGoalMet
        )
    }

    /// "7:52", or "1:05:22" from an hour up.
    static func durationText(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        return Duration.seconds(whole).formatted(.time(pattern: whole >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    /// A distance covered, to the meter under a kilometer (or a quarter mile) and to two decimals above:
    /// "802 m", "9.99 km", "0.31 mi". The unit follows `system`; the digits don't follow the device's
    /// locale, like ``distanceText(_:in:)``.
    static func actualDistanceText(_ meters: Double, in system: DistanceSystem) -> String {
        let number = FloatingPointFormatStyle<Double>.number
            .locale(Locale(identifier: "en_GB")).precision(.fractionLength(0...2))
        switch system {
        case .metric:
            if meters < 1000 { return "\(Int(meters.rounded())) m" }
            return "\((meters / 1000).formatted(number)) km"
        case .imperial:
            let miles = meters / 1609.344
            if miles < 0.25 { return "\(Int((meters / 0.9144).rounded())) yd" }
            return "\(miles.formatted(number)) mi"
        }
    }

    /// "6:32 /km" or "10:32 /mi".
    static func paceText(secondsPerKilometer: Double, in system: DistanceSystem) -> String {
        let seconds = system == .metric ? secondsPerKilometer : secondsPerKilometer * 1.609344
        let whole = Int(seconds.rounded())
        return "\(Duration.seconds(whole).formatted(.time(pattern: .minuteSecond))) /\(system == .metric ? "km" : "mi")"
    }

    /// The cards for a template at its default values, naming the parameters that set its durations,
    /// distances and repeat counts (MVP2-143), so the detail screen shows where it can be tuned.
    ///
    /// - Parameter template: The template; one that can't be instantiated has no cards.
    public static func cards(
        for template: WorkoutTemplate, distanceSystem: DistanceSystem = .deviceDefault
    ) -> [WorkoutBlockCard] {
        guard let workout = try? template.instantiate() else { return [] }
        func name(_ key: String) -> String? { template.parameters.first { $0.key == key }?.name }
        var cards = cards(for: workout.blocks, distanceSystem: distanceSystem)
        for (blockIndex, block) in template.blocks.enumerated() where blockIndex < cards.count {
            if case .parameter(let key) = block.repetitions { cards[blockIndex].repetitionsParameterName = name(key) }
            for (stepIndex, step) in block.steps.enumerated() where stepIndex < cards[blockIndex].steps.count {
                switch step.goal {
                case .time(.parameter(let key)), .distance(.parameter(let key)):
                    cards[blockIndex].steps[stepIndex].parameterName = name(key)
                default:
                    break
                }
            }
        }
        return cards
    }

    /// The symbol that marks a value set by a template parameter: a gauge with a range and a needle,
    /// new in the 2026 set (iOS 27); sliders before that.
    static var parameterSymbol: String {
        if #available(iOS 27, macOS 27, *) { "gauge.range.33to100.dotted.with.needle" } else { "slider.horizontal.3" }
    }

    /// The kind of end a goal is.
    static func end(of goal: StepGoal) -> WorkoutStepCard.End {
        switch goal {
        case .time: .time
        case .distance: .distance
        case .open: .open
        }
    }

    /// What ends a step, as the cards write it.
    static func goalText(_ goal: StepGoal, distanceSystem: DistanceSystem = .deviceDefault) -> String {
        switch goal {
        case .time(let seconds):
            Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
        case .distance(let meters):
            distanceText(meters, in: distanceSystem)
        case .open:
            "Open"
        }
    }

    /// A distance as "400 m" / "20 km", or "440 yd" / "13.1 mi" for imperial, whatever the device's
    /// locale: the system is the caller's choice, so a test or a setting decides, not the machine.
    static func distanceText(_ meters: Double, in system: DistanceSystem) -> String {
        let style = Measurement<UnitLength>.FormatStyle(
            width: .abbreviated, locale: Locale(identifier: "en_GB"), usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(0...1))
        )
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        switch system {
        case .metric:
            return (meters >= 1000 ? measurement.converted(to: .kilometers) : measurement).formatted(style)
        case .imperial:
            let yards = measurement.converted(to: .yards)
            return (yards.value >= 880 ? measurement.converted(to: .miles) : yards).formatted(style)
        }
    }

    /// The symbol before a target: a heart for heart rate, a shoe for pace, a lightning bolt for
    /// perceived effort and a horizontal bolt for power.
    static func targetSymbol(_ target: IntensityTarget) -> String {
        switch target {
        case .heartRateZone, .heartRateRange: "heart.fill"
        case .pace: paceSymbol
        case .power: "bolt.horizontal.fill"
        case .rpe: "bolt.fill"
        }
    }

    /// The running shoe with its shadow, a symbol new in the 2026 set (iOS 27); `shoe.fill` before that,
    /// where the newer name would draw nothing.
    static var paceSymbol: String {
        if #available(iOS 27, macOS 27, *) { "shoe.running.and.shadow.fill" } else { "shoe.fill" }
    }

    /// The intensity a step aims for, as the cards write it.
    static func targetText(_ target: IntensityTarget) -> String {
        switch target {
        case .heartRateZone(let zone): "HR Zone \(zone)"
        case .heartRateRange(let low, let high): "\(Int(low))–\(Int(high)) bpm"
        case .pace: "Pace target"
        case .power(let range): "\(Int(range.lowerBound))–\(Int(range.upperBound)) W"
        case .rpe(let value): "RPE \(value)"
        }
    }
}

extension StepKind {
    /// The role's name; "Warm-up" and "Cool-down" as elsewhere in the app.
    var displayName: String {
        switch self {
        case .warmup: "Warm-up"
        case .work: "Work"
        case .recovery: "Recovery"
        case .cooldown: "Cool-down"
        }
    }
}

extension DistanceSystem {
    /// The system the device's region uses; what cards and titles follow unless told otherwise.
    public static var deviceDefault: DistanceSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }
}
