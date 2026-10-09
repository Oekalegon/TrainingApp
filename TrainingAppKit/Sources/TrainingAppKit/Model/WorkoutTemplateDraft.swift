import Foundation
import TrainingCore

/// An editable copy of a ``WorkoutTemplate`` for the Structured Workout creator (MVP2-140): what the
/// editor's fields are bound to, turned back into a template by ``build()``.
///
/// Values are in the units the editor shows rather than the ones the template stores: a duration in
/// minutes (templates keep seconds), a distance in metres, a repeat count as a number. A step or block
/// points at a parameter by the parameter's draft `id`, not its `key`, so the key is free to stay
/// internal and nothing breaks while the athlete edits a name.
public struct WorkoutTemplateDraft: Equatable, Sendable {
    /// Either a fixed number or one of the template's parameters, as a step or block value.
    public enum Source: Equatable, Sendable {
        /// A fixed value, in the editor's unit for what it sets.
        case fixed(Double)
        /// The ``Parameter`` with this id.
        case parameter(UUID)
    }

    /// What ends a step.
    public enum Goal: Equatable, Sendable {
        /// A duration, in minutes.
        case time(Source)
        /// A distance, in metres.
        case distance(Source)
        /// The athlete ends the step.
        case open
    }

    /// The intensity a step aims for.
    public enum Target: Equatable, Sendable {
        /// No target.
        case none
        /// A heart-rate zone, 1 to 5.
        case zone(Int)
        /// A target kind the editor can't change (a pace, power, RPE or heart-rate range, from a
        /// template made elsewhere); it's kept as it was.
        case preserved(IntensityTarget)
    }

    /// A parameter the athlete can tune when planning the workout.
    public struct Parameter: Identifiable, Equatable, Sendable {
        /// Identifies the parameter in the draft; never saved.
        public let id: UUID
        /// The key the saved template's blocks refer to; fixed when the parameter is created.
        public let key: String
        /// The label shown when planning.
        public var name: String
        /// What the parameter sets; a step's duration takes `.minutes`, a distance `.meters` and a
        /// block's repeats `.count`.
        public var unit: ParameterUnit
        /// The starting value, in the editor's unit for ``unit``.
        public var defaultValue: Double
        /// The lowest value the slider offers, in the editor's unit.
        public var lowerBound: Double
        /// The highest value the slider offers, in the editor's unit.
        public var upperBound: Double

        /// Creates a parameter.
        public init(
            id: UUID = UUID(), key: String, name: String, unit: ParameterUnit,
            defaultValue: Double, lowerBound: Double, upperBound: Double
        ) {
            self.id = id
            self.key = key
            self.name = name
            self.unit = unit
            self.defaultValue = defaultValue
            self.lowerBound = lowerBound
            self.upperBound = upperBound
        }
    }

    /// One step of a block.
    public struct Step: Identifiable, Equatable, Sendable {
        /// Identifies the step in the draft; never saved.
        public let id: UUID
        /// The role the step plays.
        public var kind: StepKind
        /// What ends the step.
        public var goal: Goal
        /// The intensity the step aims for.
        public var target: Target

        /// Creates a step.
        public init(id: UUID = UUID(), kind: StepKind, goal: Goal, target: Target = .none) {
            self.id = id
            self.kind = kind
            self.goal = goal
            self.target = target
        }
    }

    /// Steps that repeat together.
    public struct Block: Identifiable, Equatable, Sendable {
        /// Identifies the block in the draft; never saved.
        public let id: UUID
        /// The steps of one repetition.
        public var steps: [Step]
        /// How many times the steps repeat, as a count.
        public var repetitions: Source

        /// Creates a block.
        public init(id: UUID = UUID(), steps: [Step], repetitions: Source = .fixed(1)) {
            self.id = id
            self.steps = steps
            self.repetitions = repetitions
        }
    }

    /// The id of the template this draft saves over; a duplicate gets a new one.
    public let id: UUID
    /// The template's name.
    public var name: String
    /// The short name used in generated titles, kept from the template the draft started from; the
    /// editor doesn't change it.
    public var titleName: String?
    /// For a copy, the name it was given ("… Copy"): ``titleName`` only applies while the name is still
    /// that, so a title says "Short Interval Run" rather than "… Copy" until the athlete renames the
    /// copy, after which it follows the new name. `nil` keeps ``titleName`` whatever the name.
    public var titleNameAppliesTo: String?
    /// The sport the workout is for.
    public var sport: Sport
    /// The template's parameters.
    public var parameters: [Parameter]
    /// The template's blocks.
    public var blocks: [Block]

    /// Creates a draft.
    public init(
        id: UUID = UUID(), name: String = "", titleName: String? = nil, titleNameAppliesTo: String? = nil,
        sport: Sport = .running, parameters: [Parameter] = [], blocks: [Block] = []
    ) {
        self.titleNameAppliesTo = titleNameAppliesTo
        self.id = id
        self.name = name
        self.titleName = titleName
        self.sport = sport
        self.parameters = parameters
        self.blocks = blocks
    }

    /// A draft for a template with nothing in it yet: one 10-minute Zone 2 step.
    public static func blank() -> WorkoutTemplateDraft {
        WorkoutTemplateDraft(blocks: [Block(steps: [Step.standard])])
    }

    /// The editor's number for a stored value of `unit`: minutes for a duration kept in seconds.
    static func displayValue(_ stored: Double, unit: ParameterUnit) -> Double {
        unit == .minutes ? stored / 60 : stored
    }

    /// The stored number for the editor's `value` of `unit`.
    static func storedValue(_ value: Double, unit: ParameterUnit) -> Double {
        unit == .minutes ? value * 60 : value
    }

    /// A draft of `template`, to edit it or to copy it.
    ///
    /// - Parameters:
    ///   - template: The template to start from.
    ///   - duplicating: `true` for a copy: it gets a new id and a name ending in "Copy", so saving
    ///     adds a template rather than replacing this one.
    public init(_ template: WorkoutTemplate, duplicating: Bool = false) {
        let parameters = template.parameters.map { parameter in
            Parameter(
                key: parameter.key, name: parameter.name, unit: parameter.unit,
                defaultValue: Self.displayValue(parameter.defaultValue, unit: parameter.unit),
                lowerBound: Self.displayValue(parameter.range?.lowerBound ?? parameter.defaultValue / 2, unit: parameter.unit),
                upperBound: Self.displayValue(parameter.range?.upperBound ?? parameter.defaultValue * 2, unit: parameter.unit)
            )
        }
        func source(_ value: TemplateValue<Double>, unit: ParameterUnit) -> Source {
            switch value {
            case .fixed(let number): .fixed(Self.displayValue(number, unit: unit))
            case .parameter(let key): parameters.first { $0.key == key }.map { .parameter($0.id) } ?? .fixed(0)
            }
        }
        let blocks = template.blocks.map { block in
            let steps = block.steps.map { step in
                let goal: Goal = switch step.goal {
                case .time(let value): .time(source(value, unit: .minutes))
                case .distance(let value): .distance(source(value, unit: .meters))
                case .open: .open
                }
                let target: Target = switch step.target {
                case nil: .none
                case .heartRateZone(let zone)?: .zone(zone)
                case let other?: .preserved(other)
                }
                return Step(kind: step.kind, goal: goal, target: target)
            }
            let repetitions: Source = switch block.repetitions {
            case .fixed(let count): .fixed(Double(count))
            case .parameter(let key): parameters.first { $0.key == key }.map { .parameter($0.id) } ?? .fixed(1)
            }
            return Block(steps: steps, repetitions: repetitions)
        }
        self.init(
            id: duplicating ? UUID() : template.id,
            name: duplicating ? "\(template.name) Copy" : template.name,
            titleName: duplicating ? (template.titleName ?? template.name) : template.titleName,
            titleNameAppliesTo: duplicating ? "\(template.name) Copy" : nil,
            sport: template.sport, parameters: parameters, blocks: blocks
        )
    }

    /// The ids of the parameters a step or block actually uses. A parameter nothing uses would only be a
    /// slider that does nothing, so the editor drops it and ``build()`` leaves it out.
    var referencedParameterIDs: Set<UUID> {
        var ids = Set<UUID>()
        for block in blocks {
            if case .parameter(let id) = block.repetitions { ids.insert(id) }
            for step in block.steps {
                switch step.goal {
                case .time(.parameter(let id)), .distance(.parameter(let id)): ids.insert(id)
                default: break
                }
            }
        }
        return ids
    }

    /// Removes the parameters nothing uses (see ``referencedParameterIDs``).
    mutating func pruneUnusedParameters() {
        let used = referencedParameterIDs
        parameters.removeAll { !used.contains($0.id) }
    }

    /// The parameters a value of `unit` can point at.
    public func parameters(for unit: ParameterUnit) -> [Parameter] {
        parameters.filter { $0.unit == unit }
    }

    /// What stops the draft becoming a template, in the order the editor lists its fields; empty when
    /// it can be saved.
    public var issues: [String] {
        var issues: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Give the workout a name.")
        }
        for parameter in parameters where referencedParameterIDs.contains(parameter.id) {
            let label = parameter.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty {
                issues.append("Give every parameter a name.")
            } else if !(parameter.lowerBound < parameter.upperBound) {
                issues.append("\(label): the lowest value must be below the highest.")
            } else if !(parameter.lowerBound...parameter.upperBound).contains(parameter.defaultValue) {
                issues.append("\(label): the starting value must be within its range.")
            } else if parameter.lowerBound <= 0 {
                issues.append("\(label): the lowest value must be above zero.")
            }
        }
        if blocks.isEmpty || blocks.allSatisfy({ $0.steps.isEmpty }) {
            issues.append("Add at least one step.")
        }
        if blocks.contains(where: { $0.steps.isEmpty }) && !blocks.allSatisfy({ $0.steps.isEmpty }) {
            issues.append("Every block needs a step; remove the empty one.")
        }
        for block in blocks {
            if case .fixed(let count) = block.repetitions, !(count >= 1 && count == count.rounded()) {
                issues.append("A block must repeat a whole number of times, at least once.")
            }
            for step in block.steps {
                switch step.goal {
                case .time(.fixed(let minutes)) where !(minutes > 0):
                    issues.append("A timed step needs a duration above zero.")
                case .distance(.fixed(let metres)) where !(metres > 0):
                    issues.append("A step with a distance needs a distance above zero.")
                default:
                    break
                }
            }
        }
        // A reference left dangling or pointing at the wrong kind of parameter — the editor's own
        // edits prevent both, so this only guards a hand-built draft.
        if !referencesAreValid {
            issues.append("A step uses a parameter that no longer exists.")
        }
        // The first of a kind of issue is enough: one per field would repeat itself.
        var seen = Set<String>()
        return issues.filter { seen.insert($0).inserted }
    }

    private var referencesAreValid: Bool {
        func valid(_ source: Source, unit: ParameterUnit) -> Bool {
            guard case .parameter(let id) = source else { return true }
            return parameters.contains { $0.id == id && $0.unit == unit }
        }
        return blocks.allSatisfy { block in
            valid(block.repetitions, unit: .count) && block.steps.allSatisfy { step in
                switch step.goal {
                case .time(let source): valid(source, unit: .minutes)
                case .distance(let source): valid(source, unit: .meters)
                case .open: true
                }
            }
        }
    }

    /// The template this draft describes, or `nil` while ``issues`` isn't empty.
    public func build() -> WorkoutTemplate? {
        issues.isEmpty ? buildUnchecked() : nil
    }

    /// The template this draft describes, without checking ``issues`` first; for a caller that has
    /// just done so and shouldn't pay for it twice. Meaningless while the draft has issues.
    func buildUnchecked() -> WorkoutTemplate {
        func key(_ id: UUID) -> String { parameters.first { $0.id == id }?.key ?? "" }
        func value(_ source: Source, unit: ParameterUnit) -> TemplateValue<Double> {
            switch source {
            case .fixed(let number): .fixed(Self.storedValue(number, unit: unit))
            case .parameter(let id): .parameter(key(id))
            }
        }
        let templateBlocks = blocks.map { block in
            let steps = block.steps.map { step in
                let goal: TemplateStepGoal = switch step.goal {
                case .time(let source): .time(value(source, unit: .minutes))
                case .distance(let source): .distance(value(source, unit: .meters))
                case .open: .open
                }
                let target: IntensityTarget? = switch step.target {
                case .none: nil
                case .zone(let zone): .heartRateZone(zone)
                case .preserved(let target): target
                }
                return TemplateStep(kind: step.kind, goal: goal, target: target)
            }
            let repetitions: TemplateValue<Int> = switch block.repetitions {
            case .fixed(let count): .fixed(Int(count))
            case .parameter(let id): .parameter(key(id))
            }
            return TemplateBlock(steps: steps, repetitions: repetitions)
        }
        let used = referencedParameterIDs
        let templateParameters = parameters.filter { used.contains($0.id) }.map { parameter in
            WorkoutTemplateParameter(
                key: parameter.key,
                name: parameter.name.trimmingCharacters(in: .whitespacesAndNewlines),
                unit: parameter.unit,
                defaultValue: Self.storedValue(parameter.defaultValue, unit: parameter.unit),
                range: Self.storedValue(parameter.lowerBound, unit: parameter.unit)...Self.storedValue(parameter.upperBound, unit: parameter.unit)
            )
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let keepsTitleName = titleNameAppliesTo == nil || titleNameAppliesTo == trimmedName
        return WorkoutTemplate(
            id: id, name: trimmedName, titleName: keepsTitleName ? titleName : nil,
            sport: sport, parameters: templateParameters, blocks: templateBlocks
        )
    }
}

extension WorkoutTemplateDraft.Step {
    /// A 10-minute Zone 2 work step, what a new step starts as.
    static var standard: Self {
        Self(kind: .work, goal: .time(.fixed(10)), target: .zone(2))
    }
}
