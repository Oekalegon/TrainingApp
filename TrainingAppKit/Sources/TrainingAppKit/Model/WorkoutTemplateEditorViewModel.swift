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
        self.isNew = isNew
    }

    /// The navigation title.
    public var title: String { isNew ? "New Workout" : "Edit Workout" }

    /// What stops the draft being saved, as ``WorkoutTemplateDraft/issues``.
    public var issues: [String] { draft.issues }

    /// Whether ``save()`` has something valid to save.
    public var canSave: Bool { draft.issues.isEmpty && !isSaving }

    /// The title the workout would get when planned at its default values, e.g. "40min Easy Run";
    /// `nil` while the draft can't be saved.
    public var defaultTitlePreview: String? {
        draft.build()?.defaultTitle(distanceSystem: distanceSystem)
    }

    // MARK: Parameters

    /// Adds a parameter of `unit` with a name, starting value and range that make sense for it, and
    /// returns its id.
    @discardableResult
    public func addParameter(unit: ParameterUnit) -> UUID {
        let keys = Set(draft.parameters.map(\.key))
        var number = draft.parameters.count + 1
        while keys.contains("parameter\(number)") { number += 1 }
        let parameter: WorkoutTemplateDraft.Parameter
        switch unit {
        case .minutes:
            parameter = .init(key: "parameter\(number)", name: "Duration", unit: unit, defaultValue: 20, lowerBound: 10, upperBound: 40)
        case .meters:
            parameter = .init(key: "parameter\(number)", name: "Distance", unit: unit, defaultValue: 400, lowerBound: 200, upperBound: 1000)
        case .count:
            parameter = .init(key: "parameter\(number)", name: "Repeats", unit: unit, defaultValue: 4, lowerBound: 2, upperBound: 10)
        }
        draft.parameters.append(parameter)
        return parameter.id
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

    /// Adds a block with one step after the others.
    public func addBlock() {
        draft.blocks.append(.init(steps: [.standard]))
    }

    /// Removes the block with id `blockID`.
    public func removeBlock(id blockID: UUID) {
        draft.blocks.removeAll { $0.id == blockID }
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
            saveError = "Couldn't save this workout: \(error.localizedDescription)"
            return false
        }
    }
}
