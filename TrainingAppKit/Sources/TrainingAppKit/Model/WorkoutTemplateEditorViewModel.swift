import Foundation
import TrainingCore

/// Drives the Structured Workout creator (MVP2-140, design doc §2.4): creating a workout template,
/// editing one of the athlete's own, or editing a copy of any template, then saving it into
/// ``TrainingModel``.
///
/// The fields edit a ``WorkoutTemplateDraft``; nothing is saved until ``save()``. Saving over an
/// existing template changes what the library offers from then on, but not the plans already made
/// from it: each plan instantiated a workout of its own (MVP2-15).
@Observable
@MainActor
public final class WorkoutTemplateEditorViewModel: Identifiable {
    private let model: TrainingModel

    /// The template being edited; the editor's fields are bound to it.
    public var draft: WorkoutTemplateDraft
    /// What the draft was when the editor opened, to tell whether there is anything to lose.
    private let initialDraft: WorkoutTemplateDraft
    /// `true` when ``save()`` adds a template (a new one or a copy), `false` when it replaces one.
    public let isNew: Bool
    /// How distances are written in the default-title preview; defaults to the device's measurement
    /// system.
    public var distanceSystem: DistanceSystem = Locale.current.measurementSystem == .metric ? .metric : .imperial

    /// Set when ``save()`` fails — a store failure. The sheet shows this as a blocking alert.
    public private(set) var saveError: String?
    /// Whether ``save()`` is running.
    public private(set) var isSaving = false

    /// Called after a template was saved, so the library can show it.
    @ObservationIgnored
    public var onSaved: (@MainActor () -> Void)?

    /// Creates an editor view model.
    ///
    /// - Parameters:
    ///   - model: The training model to save the template into.
    ///   - draft: What to edit; defaults to a blank template.
    ///   - isNew: Whether saving adds a template rather than replacing one. Defaults to `true`.
    public init(model: TrainingModel, draft: WorkoutTemplateDraft = .blank(), isNew: Bool = true) {
        self.model = model
        self.draft = draft
        self.initialDraft = draft
        self.isNew = isNew
    }

    /// The navigation title.
    public var title: String { isNew ? "New Workout Template" : "Edit Workout Template" }

    /// Whether the athlete changed anything since the editor opened; the sheet then asks before
    /// discarding.
    public var hasChanges: Bool { draft != initialDraft }

    /// What the sheet shows about the draft: what stops it being saved, or else the title it would get.
    public struct Summary: Equatable, Sendable {
        /// What stops the draft being saved, as ``WorkoutTemplateDraft/issues``; empty when it can be.
        public let issues: [String]
        /// The title the workout would get when planned at its default values, e.g. "40min Easy Run";
        /// `nil` while ``issues`` isn't empty.
        public let defaultTitle: String?
    }

    /// The draft checked once: the sheet reads this a single time per render instead of validating for
    /// each of the save button, the issue list and the title.
    public var summary: Summary {
        let issues = draft.issues
        let title = issues.isEmpty ? draft.buildUnchecked().defaultTitle(distanceSystem: distanceSystem) : nil
        return Summary(issues: issues, defaultTitle: title)
    }

    /// Whether ``save()`` has something valid to save.
    public var canSave: Bool { draft.issues.isEmpty && !isSaving }

    // MARK: Parameters

    /// Adds a parameter of `unit` with a starting value and range that make sense for it, and returns
    /// its id. The step or block that asked for it points at it.
    ///
    /// - Parameters:
    ///   - name: What the slider is called when planning, e.g. "Recovery duration"; made unique among
    ///     the parameters ("… 2") so two sliders are never labelled alike. Defaults to a name for the
    ///     unit.
    ///   - defaultValue: The starting value, in the editor's unit, when the parameter replaces a fixed
    ///     value, so nothing changes until the athlete edits it; its range is built around it (half to
    ///     double for a duration or distance; two below to four above for a count). Without one, or
    ///     with one that isn't positive, the unit's usual starting value and range are used.
    @discardableResult
    public func addParameter(unit: ParameterUnit, name: String? = nil, defaultValue: Double? = nil) -> UUID {
        let keys = Set(draft.parameters.map(\.key))
        var number = draft.parameters.count + 1
        while keys.contains("parameter\(number)") { number += 1 }
        let key = "parameter\(number)"
        let baseName = name ?? { switch unit { case .minutes: "Duration"; case .meters: "Distance"; case .count: "Repeats" } }()
        let names = Set(draft.parameters.map(\.name))
        var uniqueName = baseName
        var suffix = 2
        while names.contains(uniqueName) {
            uniqueName = "\(baseName) \(suffix)"
            suffix += 1
        }
        let parameter: WorkoutTemplateDraft.Parameter
        if let value = defaultValue, value > 0 {
            let range: ClosedRange<Double> = unit == .count ? max(1, value - 2)...(value + 4) : (value / 2)...(value * 2)
            parameter = .init(
                key: key, name: uniqueName, unit: unit,
                defaultValue: value, lowerBound: range.lowerBound, upperBound: range.upperBound
            )
        } else {
            switch unit {
            case .minutes:
                parameter = .init(key: key, name: uniqueName, unit: unit, defaultValue: 20, lowerBound: 10, upperBound: 40)
            case .meters:
                parameter = .init(key: key, name: uniqueName, unit: unit, defaultValue: 400, lowerBound: 200, upperBound: 1000)
            case .count:
                parameter = .init(key: key, name: uniqueName, unit: unit, defaultValue: 4, lowerBound: 2, upperBound: 10)
            }
        }
        draft.parameters.append(parameter)
        return parameter.id
    }

    /// Drops the parameters no step or block uses any more; called after a value stops using one and
    /// after steps or blocks are removed.
    public func pruneUnusedParameters() {
        draft.pruneUnusedParameters()
    }

    /// Removes a parameter. A step or block that used it keeps the parameter's starting value as a
    /// fixed one.
    public func removeParameter(id: UUID) {
        guard let parameter = draft.parameters.first(where: { $0.id == id }) else { return }
        draft.parameters.removeAll { $0.id == id }
        let fixed = WorkoutTemplateDraft.Source.fixed(parameter.defaultValue)
        for blockIndex in draft.blocks.indices {
            if draft.blocks[blockIndex].repetitions == .parameter(id) {
                draft.blocks[blockIndex].repetitions = fixed
            }
            for stepIndex in draft.blocks[blockIndex].steps.indices {
                switch draft.blocks[blockIndex].steps[stepIndex].goal {
                case .time(.parameter(id)): draft.blocks[blockIndex].steps[stepIndex].goal = .time(fixed)
                case .distance(.parameter(id)): draft.blocks[blockIndex].steps[stepIndex].goal = .distance(fixed)
                default: break
                }
            }
        }
    }

    // MARK: Blocks and steps

    /// Adds a block with one step: a step that runs once. It goes after the others, except that a
    /// cool-down closing the workout stays last.
    ///
    /// - Returns: The new step's id, so the editor can open it.
    @discardableResult
    public func addBlock() -> UUID {
        let step = WorkoutTemplateDraft.Step.standard
        draft.blocks.insert(.init(steps: [step]), at: insertionIndex)
        return step.id
    }

    /// Adds a block that repeats a hard step and a recovery step four times (the creator's "Add
    /// Repeat"), which the athlete then edits; placed like ``addBlock()``.
    ///
    /// - Returns: The first new step's id, so the editor can open it.
    @discardableResult
    public func addRepeat() -> UUID {
        let work = WorkoutTemplateDraft.Step(kind: .work, goal: .time(.fixed(1)), target: .zone(4))
        let recovery = WorkoutTemplateDraft.Step(kind: .recovery, goal: .time(.fixed(1)), target: .zone(1))
        draft.blocks.insert(.init(steps: [work, recovery], repetitions: .fixed(4)), at: insertionIndex)
        return work.id
    }

    /// Where a new block goes: after the other steps but before a closing cool-down, since nothing
    /// added should land after it.
    private var insertionIndex: Int { draft.insertionIndex }

    /// Moves the block with id `id` to where `targetID` is, as a drop does; the opening warm-up and the
    /// closing cool-down never move, nor can a block be dropped past them.
    public func moveBlock(id: UUID, toPositionOf targetID: UUID) {
        draft.moveBlock(id: id, toPositionOf: targetID)
    }

    /// Moves the block with id `id` up (`-1`) or down (`1`) among the movable blocks.
    public func moveBlock(id: UUID, by offset: Int) {
        draft.moveBlock(id: id, by: offset)
    }

    /// Makes the block with id `blockID` repeat `count` times; a step that ran once then shows as a
    /// "Repeat" card.
    public func setRepetitions(_ count: Int, inBlock blockID: UUID) {
        guard let index = draft.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        draft.blocks[index].repetitions = .fixed(Double(count))
    }

    /// Removes the block with id `blockID`.
    public func removeBlock(id blockID: UUID) {
        draft.blocks.removeAll { $0.id == blockID }
        draft.pruneUnusedParameters()
    }

    /// Adds a step to the end of the block with id `blockID`.
    public func addStep(toBlock blockID: UUID) {
        guard let index = draft.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        draft.blocks[index].steps.append(.standard)
    }

    /// Removes the steps at `offsets` from the block with id `blockID`.
    public func removeSteps(at offsets: IndexSet, fromBlock blockID: UUID) {
        guard let index = draft.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        draft.blocks[index].steps.remove(atOffsets: offsets)
        removeBlockIfEmpty(at: index)
    }

    /// A block with no steps is meaningless, so removing its last step removes it.
    private func removeBlockIfEmpty(at index: Int) {
        if draft.blocks[index].steps.isEmpty { draft.blocks.remove(at: index) }
        draft.pruneUnusedParameters()
    }

    /// Removes the step with id `stepID` from the block with id `blockID`.
    public func removeStep(id stepID: UUID, fromBlock blockID: UUID) {
        guard let index = draft.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        draft.blocks[index].steps.removeAll { $0.id == stepID }
        removeBlockIfEmpty(at: index)
    }

    /// Moves the steps at `source` to `destination` within the block with id `blockID`.
    public func moveSteps(from source: IndexSet, to destination: Int, inBlock blockID: UUID) {
        guard let index = draft.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        draft.blocks[index].steps.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: Saving

    /// Saves the template — `true` on success, in which case the sheet dismisses; `false` leaves
    /// ``saveError`` set for the sheet to show, or means the draft isn't valid yet.
    @discardableResult
    public func save() async -> Bool {
        // Guards against a double-tap landing before the `Task` wrapping this call has started.
        guard !isSaving, let template = draft.build() else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await model.add(template)
            onSaved?()
            return true
        } catch {
            saveError = "Couldn't save this workout template: \(error.localizedDescription)"
            return false
        }
    }
}
