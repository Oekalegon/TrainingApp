import Foundation
import TrainingCore

/// Turns a ``PlanRequest`` into a ``PlanProposal`` (MVP5-146). The Create Plan wizard calls the plan
/// generator through this closure instead of naming ``PlanGenerator``, so another generator (an
/// LLM-assisted one, say) can be dropped in without touching the wizard.
public typealias PlanGenerating = @Sendable (PlanRequest) async throws -> PlanProposal

/// The steps of the Create Plan wizard, in order.
public enum CreatePlanStep: Int, CaseIterable, Identifiable, Sendable {
    case startDate, races, paradigm, preferences, peakVolume, review

    public var id: Int { rawValue }

    /// The step's title.
    public var title: String {
        switch self {
        case .startDate: "Start Date"
        case .races: "Races"
        case .paradigm: "Training Approach"
        case .preferences: "Availability"
        case .peakVolume: "Weekly Volume"
        case .review: "Review"
        }
    }
}

/// Where a race falls against the plan being made.
public enum RaceWindowState: Equatable, Sendable {
    /// Between the start date and the target race (or the target race itself).
    case inWindow
    /// Before the plan starts.
    case beforeStart
    /// After the target race, so the plan does not reach it.
    case afterTarget
    /// No target race is chosen yet, so there is no window end to compare with.
    case noTarget
}

/// Drives the Create Plan wizard (MVP5-146): the choices that become a ``PlanRequest``, what each step
/// needs to be complete, and the generate and commit actions of the review step.
///
/// ``generate()`` asks the generator (``PlanGenerating``, the plan generator by default) for a proposal from
/// the start date, the races, the paradigm, the micro length and the plan's preferences, and reads what activating it
/// would replace (``details``, MVP5-121). ``commit(activate:)`` then stores it with
/// ``TrainingModel/commit(_:named:activate:acceptingRisks:asOf:)``: as a **draft** by default, which changes nothing in
/// the calendar, or as the active plan once the athlete has seen what it replaces and, for a plan with risks, accepted
/// them (``acceptsRisks``). The Plans tab compares a draft's form against the active plan's.
///
/// The plan's preferences start as the athlete's Running Availability and can be changed for this
/// plan only; nothing is written back to the athlete. A proposal belongs to the exact choices it was
/// generated from: changing any of them hides it (``proposal`` is `nil` again) until the next
/// ``generate()``, so the review never shows or commits a stale plan.
///
/// Both async actions read the choices before the first `await`, ignore a second call while one runs,
/// and report a failure in ``failure`` instead of closing the sheet; only ``commit()`` returning a plan
/// means the wizard is done.
@Observable
@MainActor
public final class CreatePlanViewModel {
    /// The micro lengths a plan can have, in days.
    public static let microLengths = [7, 10, 14]
    /// The weekly volume to start from when the athlete has no recent running, in seconds (3 hours).
    public static let fallbackStartingVolume: TimeInterval = 3 * 3600
    /// How far ahead the races offered are read, in days.
    private static let raceHorizonDays = 730
    /// The weeks of recent running averaged into the starting volume.
    private static let startingVolumeWeeks = 4
    /// The weeks of recent running averaged into the current volume a conditioning phase builds up from (MVP5-160).
    private static let currentVolumeWeeks = 2

    /// Everything the generated plan depends on; a proposal is shown only while this still equals the
    /// value it was generated for.
    struct Inputs: Equatable {
        var start: Date
        var races: [Race]
        var paradigm: TrainingParadigm
        var microLength: Int
        var preferences: PlanPreferences
        var peak: PeakVolumeDraft
        var startVolume: PeakVolumeDraft
    }

    private let model: TrainingModel
    private let generator: PlanGenerating
    private let now: @MainActor () -> Date
    @ObservationIgnored
    private let addRaceViewModel: @MainActor (Date) -> RaceSheetViewModel

    // MARK: Choices

    /// The wizard's current step.
    public private(set) var step: CreatePlanStep = .startDate
    /// The first day of the plan, the start of a day in the athlete's time zone.
    public var startDate: Date {
        get { start }
        set { start = calendar.startOfDay(for: newValue) }
    }
    private var start: Date
    /// The ids of the races the athlete ticked.
    public private(set) var selectedRaceIDs: Set<UUID> = []
    /// Priorities chosen for this plan only; a race not here keeps its own.
    public private(set) var priorityOverrides: [UUID: RacePriority] = [:]
    /// The paradigm, 80/20 polarized by default.
    public var paradigm: TrainingParadigm = .polarized8020
    /// The micro length in days (one of ``microLengths``).
    public var microLength = 7
    /// The plan's preferences, started from the athlete's and changed for this plan only.
    public var preferences: PlanPreferences
    /// The peak weekly volume field (MVP5-134), required (MVP5-162). Changing its measure puts the starting volume
    /// back to the athlete's running in that measure.
    var peak: PeakVolumeDraft {
        didSet {
            if oldValue.measure != peak.measure || oldValue.distanceSystem != peak.distanceSystem {
                startEdited = false
                prefillStart()
            }
        }
    }
    /// The starting weekly volume field (MVP5-162), required: in the measure of the peak (time, or distance), pre-filled
    /// from the last four weeks of running until the athlete types their own.
    var startVolume: PeakVolumeDraft {
        didSet { if !isPrefilling { startEdited = true } }
    }
    @ObservationIgnored private var startEdited = false
    @ObservationIgnored private var isPrefilling = false
    /// The plan's name; ``reviewName`` offers one while this is empty.
    public var name = ""

    // MARK: State

    /// The athlete's upcoming races, read by ``load()``.
    public private(set) var upcomingRaces: [Race] = []
    /// Set when ``load()`` can't read the races.
    public private(set) var loadError: String?
    /// Whether ``generate()`` is running.
    public private(set) var isGenerating = false
    /// Whether ``commit()`` is running.
    public private(set) var isCommitting = false
    /// Why the last generate or commit failed; cleared when either starts.
    public private(set) var failure: String?
    /// The plan made by ``commit()``, once it has.
    public private(set) var committedPlan: TrainingPlan?
    private var generated: (inputs: Inputs, proposal: PlanProposal, details: PlanPreviewDetails?, note: String?)?

    /// Creates the wizard's view model.
    ///
    /// - Parameters:
    ///   - model: The app's training model: the athlete, their activities, templates and races, and where the draft is stored.
    ///   - generator: Makes the proposal; the plan generator by default.
    ///   - now: The current time; replaced by tests.
    ///   - addRaceViewModel: Makes the view model of the sheet for a new race, given its default date.
    public init(
        model: TrainingModel,
        generator: @escaping PlanGenerating = { try await PlanGenerator.generate($0) },
        now: @escaping @MainActor () -> Date = { .now },
        addRaceViewModel: (@MainActor (Date) -> RaceSheetViewModel)? = nil
    ) {
        self.model = model
        self.generator = generator
        self.now = now
        self.addRaceViewModel = addRaceViewModel ?? { RaceSheetViewModel(model: model, date: $0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.athlete.timeZone
        start = calendar.startOfDay(for: now())
        preferences = PlanPreferences(runAvailability: model.athlete.runAvailability)
        // Time, not the draft's default TRIMP: the generator does not plan by TRIMP.
        peak = PeakVolumeDraft(measure: .duration)
        startVolume = PeakVolumeDraft(measure: .duration)
        prefillStart()
    }

    /// Fills the starting volume from the last four weeks of running, in the measure of the peak (a distance at the
    /// easy pace), unless the athlete has typed their own. Called when the athlete's runs are read, so a plan opened
    /// before they were loaded still gets them (MVP5-162).
    private func prefillStart() {
        guard !startEdited else { return }
        let seconds = startingVolume(asOf: calendar.startOfDay(for: now()))
        isPrefilling = true
        defer { isPrefilling = false }
        if peak.measure == .distance {
            let easySecondsPerMeter = model.athlete.paceModel.secondsPerMeter(atZone: 2)
            guard easySecondsPerMeter.isFinite, easySecondsPerMeter > 0 else {
                // No pace to turn the running into a distance: leave the field empty, in the peak's measure, for the athlete to fill in.
                startVolume = PeakVolumeDraft(measure: .distance, distanceSystem: peak.distanceSystem)
                return
            }
            startVolume = PeakVolumeDraft(measure: .distance, baseValue: seconds / easySecondsPerMeter, distanceSystem: peak.distanceSystem)
        } else {
            startVolume = PeakVolumeDraft(measure: .duration, baseValue: seconds, distanceSystem: peak.distanceSystem)
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.athlete.timeZone
        return calendar
    }

    /// The first day the plan can start: today.
    public var earliestStart: Date { calendar.startOfDay(for: now()) }

    /// The weekdays in the order the athlete's week starts, for the availability list.
    var weekdays: [Weekday] { model.athlete.weekStartsOn.weekOrder }

    /// The sheet for adding a race from the races step, defaulting to `date`.
    public func newRaceViewModel(date: Date? = nil) -> RaceSheetViewModel {
        addRaceViewModel(date ?? startDate)
    }

    // MARK: Loading

    /// Reads the athlete's upcoming races. Races from the start date on are offered; a race the
    /// athlete just added is selected by ``raceWasAdded(_:)``.
    public func load() async {
        let from = earliestStart
        guard let horizon = calendar.date(byAdding: .day, value: Self.raceHorizonDays, to: from) else { return }
        do {
            let races = try await model.stores.raceStore.races(in: from...horizon)
            upcomingRaces = races.sorted { ($0.date, $0.name) < ($1.date, $1.name) }
            loadError = nil
            selectedRaceIDs.formIntersection(Set(upcomingRaces.map(\.id)))
            if selectedRaceIDs.isEmpty, let first = upcomingRaces.first(where: { $0.priority == .primary }) {
                selectedRaceIDs = [first.id]
            }
        } catch {
            loadError = "Couldn't read your races: \(error.localizedDescription)"
        }
        // The athlete's runs do not depend on the races: a failed races read still fills the starting volume.
        prefillStart()
    }

    /// Re-reads the races after the new-race sheet saved `race`, and selects it.
    public func raceWasAdded(_ race: Race?) async {
        await load()
        if let race, upcomingRaces.contains(where: { $0.id == race.id }) { selectedRaceIDs.insert(race.id) }
    }

    // MARK: Races

    /// Ticks or unticks `race`. A race outside the plan window can't be ticked.
    public func toggle(_ race: Race) {
        if selectedRaceIDs.contains(race.id) {
            selectedRaceIDs.remove(race.id)
            priorityOverrides[race.id] = nil
        } else if windowState(of: race) != .beforeStart && windowState(of: race) != .afterTarget {
            selectedRaceIDs.insert(race.id)
        }
    }

    /// The priority `race` has in this plan: the one chosen here, else its own.
    public func priority(of race: Race) -> RacePriority { priorityOverrides[race.id] ?? race.priority }

    /// Sets the priority of `race` for this plan only; the race itself is not changed.
    public func setPriority(_ priority: RacePriority, of race: Race) {
        priorityOverrides[race.id] = priority == race.priority ? nil : priority
    }

    /// The race the plan builds towards: the earliest ticked race that is primary in this plan.
    public var targetRace: Race? {
        primaryCandidates.min { $0.date < $1.date }
    }

    /// The ticked races from the start date on that are primary in this plan.
    private var primaryCandidates: [Race] {
        chosenRaces.filter { priority(of: $0) == .primary && calendar.startOfDay(for: $0.date) >= startDate }
    }

    private var chosenRaces: [Race] {
        upcomingRaces.filter { selectedRaceIDs.contains($0.id) }
    }

    /// Where `race` falls against the start date and the target race.
    public func windowState(of race: Race) -> RaceWindowState {
        let day = calendar.startOfDay(for: race.date)
        if day < startDate { return .beforeStart }
        guard let target = targetRace else { return .noTarget }
        return day > calendar.startOfDay(for: target.date) ? .afterTarget : .inWindow
    }

    /// The ticked races inside the plan window, with this plan's priorities applied, in date order.
    public var includedRaces: [Race] {
        chosenRaces
            .filter { windowState(of: $0) == .inWindow }
            .map { race in
                var race = race
                race.priority = priority(of: race)
                race.date = calendar.startOfDay(for: race.date)
                return race
            }
    }

    /// Ticked races left out of the plan because they fall before its start or after its target.
    public var excludedRaces: [Race] {
        chosenRaces.filter { windowState(of: $0) != .inWindow }
    }

    // MARK: Paradigm

    /// The paradigms offered.
    public var paradigms: [TrainingParadigm] { TrainingParadigm.builtIn }

    /// The marathon-calibration warning for the chosen paradigm and target race (MVP5-143), if it applies.
    public var calibrationWarning: CalibrationWarning? { paradigm.calibrationWarning(for: targetRace) }

    // MARK: Preferences

    /// Whether this plan's availability differs from the athlete's own.
    public var hasAvailabilityOverride: Bool {
        preferences.runAvailability != model.athlete.runAvailability
    }

    /// Sets this plan's availability. The athlete's own is not touched.
    public func setAvailability(_ availability: RunAvailability) {
        preferences.runAvailability = availability
    }

    /// Goes back to the athlete's availability for this plan.
    public func resetAvailability() {
        preferences.runAvailability = model.athlete.runAvailability
    }

    /// Whether the paradigm has a conditioning phase to ask about.
    public var offersConditioning: Bool { paradigm.phases.contains(.conditioning) }

    /// Whether the paradigm has a specific phase, the only one where TrainingKit places a special block (MVP5-161);
    /// 80/20 has none, so asking for blocks there could only end in a compromise.
    public var offersSpecialBlocks: Bool { paradigm.phases.contains(.specific) }

    /// How many special blocks the athlete wants, 0 to 2, and 0 when the approach has no specific phase: a count kept
    /// from before the approach changed is not sent (MVP5-161).
    public var specialBlocks: Int {
        get { offersSpecialBlocks ? preferences.specialBlocks : 0 }
        set { preferences.specialBlocks = min(max(newValue, 0), 2) }
    }

    /// Whether the target race is an ultra, where a special block is a long run on two consecutive days
    /// and not two sessions in one day (MVP5-161).
    public var targetIsUltra: Bool { targetRace?.isUltra ?? false }

    /// How many runs a week the athlete wants, or `nil` for a run on every day available (MVP5-159), never
    /// more than ``maxRunsPerWeek``: a value kept from before days were switched off, or their runs lowered,
    /// reads as the new maximum.
    public var runsPerWeek: Int? {
        get { preferences.runsPerWeek.map { min($0, maxRunsPerWeek) } }
        set { preferences.runsPerWeek = newValue }
    }

    /// The most runs a week the availability allows: the runs of each available day (more than one when the athlete
    /// allows two runs in a day, MVP5-132), at least 1.
    public var maxRunsPerWeek: Int {
        max(Weekday.allCases.reduce(0) { $0 + (preferences.runAvailability.isAvailable(on: $1) ? preferences.runAvailability.runs(on: $1) : 0) }, 1)
    }

    // MARK: Validation

    /// Why `step` is not complete, or `nil` when it is.
    public func problem(in step: CreatePlanStep) -> String? {
        switch step {
        case .startDate:
            return startDate < earliestStart ? "The plan can't start in the past." : nil
        case .races:
            let primaries = primaryCandidates
            if chosenRaces.isEmpty { return "Choose the race the plan builds towards." }
            if primaries.isEmpty { return "Make one of the races primary: the plan is built back from it." }
            if primaries.count > 1 { return "Only one race can be primary. Make the others secondary or tertiary." }
            return nil
        case .paradigm:
            return Self.microLengths.contains(microLength) ? nil : "Choose 7, 10 or 14 days."
        case .preferences:
            let available = Weekday.allCases.contains { preferences.runAvailability.isAvailable(on: $0) }
            return available ? nil : "Choose at least one day you could run."
        case .peakVolume:
            switch startVolume.validation {
            case .empty: return "Enter the weekly volume to start from."
            case .invalid, .tooLarge: return startVolume.message
            case .valid: break
            }
            switch peak.validation {
            case .empty: return "Enter the most you want to run in a week."
            case .invalid, .tooLarge: return peak.message
            case .valid: break
            }
            if peak.measure == .trimp { return "The plan generator doesn't plan by TRIMP. Enter the peak in hours or distance." }
            if startVolume.measure != peak.measure { return "Enter the starting volume in \(peak.unitLabel)." }
            if let starting = startVolume.value, let top = peak.value, starting > top { return "The starting volume is above your peak." }
            return nil
        case .review:
            return effectiveName.isEmpty ? "A plan needs a name." : nil
        }
    }

    /// The volume step's problem when neither field is showing it already: an empty field, a start in another measure or a
    /// start above the peak. A field that is invalid shows its own message under it, so the step shows this only otherwise
    /// (MVP5-162).
    public var volumeStepProblem: String? {
        guard startVolume.message == nil, peak.message == nil else { return nil }
        return problem(in: .peakVolume)
    }

    /// Whether the steps before the review are all complete.
    public var isReadyToGenerate: Bool {
        CreatePlanStep.allCases.filter { $0 != .review }.allSatisfy { problem(in: $0) == nil }
    }

    /// Whether the wizard can move on from the current step.
    public var canAdvance: Bool { step != .review && problem(in: step) == nil && !isBusy }
    /// Whether there is an earlier step.
    public var canGoBack: Bool { step != .startDate && !isBusy }
    /// Whether a generate or commit is running.
    public var isBusy: Bool { isGenerating || isCommitting }

    /// Moves to the next step if the current one is complete.
    public func next() {
        guard canAdvance, let following = CreatePlanStep(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    /// Moves to the previous step.
    public func back() {
        guard canGoBack, let previous = CreatePlanStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// The name used when none is typed: "<target race> plan".
    public var reviewName: String {
        targetRace.map { "\($0.name) plan" } ?? ""
    }

    private var effectiveName: String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? reviewName : typed
    }

    // MARK: Generate

    var currentInputs: Inputs {
        Inputs(start: startDate, races: includedRaces, paradigm: paradigm, microLength: microLength, preferences: preferences, peak: peak, startVolume: startVolume)
    }

    /// The generated proposal, while it still matches the choices it was made from.
    public var proposal: PlanProposal? {
        guard let generated, generated.inputs == currentInputs else { return nil }
        return generated.proposal
    }

    /// The micro-cycles with their workouts, the projected form and what activating would replace, for the proposal
    /// shown; `nil` with no proposal or when the preview could not be made (see ``previewNote``) (MVP5-121).
    public var details: PlanPreviewDetails? {
        guard let generated, generated.inputs == currentInputs else { return nil }
        return generated.details
    }

    /// Whether the proposal has no risk findings, so it can be activated without accepting any.
    public var isAcceptable: Bool { proposal?.isAcceptable ?? true }

    /// Set when the proposal was made but its preview was not, so what activating would replace is unknown;
    /// the plan can still be stored as a draft. Like the proposal, it belongs to the choices it was made from.
    public var previewNote: String? {
        guard let generated, generated.inputs == currentInputs else { return nil }
        return generated.note
    }

    /// Whether the athlete accepted the risks of the proposal shown; put back to `false` for every new proposal, so
    /// accepting the risks of one plan never carries over to the next.
    public var acceptsRisks = false

    /// Whether the plan can be activated now: there is a proposal, what it would replace is known, and its risks are
    /// accepted if it has any.
    public var canActivate: Bool {
        guard let proposal, details != nil else { return false }
        return proposal.isAcceptable || acceptsRisks
    }

    /// A readable form of ``proposal`` for the review step.
    public var summary: PlanProposalSummary? {
        proposal.map { PlanProposalSummary($0, calendar: calendar) }
    }

    /// The request the generator is given for the current choices, or why it can't be made.
    func makeRequest() -> PlanRequest? {
        guard isReadyToGenerate, let target = targetRace.map({ race -> Race in
            var race = race
            race.priority = .primary
            race.date = calendar.startOfDay(for: race.date)
            return race
        }) else { return nil }
        let others = includedRaces.filter { $0.id != target.id }
        let today = calendar.startOfDay(for: now())
        let leadDays = (calendar.dateComponents([.day], from: startDate, to: target.date).day ?? 0) + 1
        var preferences = preferences
        preferences.runsPerWeek = runsPerWeek
        preferences.specialBlocks = specialBlocks
        // The plan is in the measure of the peak: time, or distance (the generator plans it as the same time at the
        // easy pace). Both volumes are the athlete's own entries (MVP5-162); TRIMP is not used, the generator does
        // not plan by it, so a TRIMP peak makes no request.
        guard peak.measure != .trimp, startVolume.measure == peak.measure, let startAmount = startVolume.value, let peakAmount = peak.value, startAmount <= peakAmount else { return nil }
        let measure: VolumeMeasure = peak.measure == .distance ? .distanceMeters : .durationSeconds
        preferences.maxWeeklyVolume[.running] = VolumeTarget(measure: measure, amount: peakAmount)
        let hard = paradigm.maxHardSessionsPerMicro[microLength] ?? 2
        guard
            let startTarget = VolumeTarget(measure: measure, amount: startAmount),
            let peakTarget = VolumeTarget(measure: measure, amount: peakAmount)
        else { return nil }
        // A conditioning phase builds up from what the athlete runs now to the starting volume of base (MVP5-160);
        // the last two weeks stand for "now", the last four for the base.
        var currentTarget: VolumeTarget?
        if preferences.includeConditioning, let current = currentVolume(asOf: today) {
            let amount = measure == .distanceMeters ? current / model.athlete.paceModel.secondsPerMeter(atZone: 2) : current
            if amount.isFinite, amount < startTarget.amount { currentTarget = VolumeTarget(measure: measure, amount: amount) }
        }
        return PlanRequest(
            targetRace: target, otherRaces: others, paradigm: paradigm,
            macro: PlanMacro.template(
                for: paradigm, microLengthDays: microLength, leadTimeDays: max(leadDays, 0),
                includeConditioning: preferences.includeConditioning
            ),
            meso: MesocycleTemplate(name: MesocycleTemplate.threeToOne.name, microRoles: MesocycleTemplate.threeToOne.microRoles, microLengthDays: microLength),
            preferences: preferences, athlete: model.athlete, today: today, start: startDate,
            templates: BuiltInWorkoutTemplates.all + model.templates.filter { !$0.isArchived },
            startingVolume: startTarget, peakVolume: peakTarget, currentVolume: currentTarget,
            hardSessionsPerMicro: hard, longRunsPerMicro: 1, activities: model.activities
        )
    }

    /// The weekly running time to start the plan from: the last four weeks of running averaged to 7
    /// days, or ``fallbackStartingVolume`` when there is none.
    func startingVolume(asOf today: Date) -> TimeInterval {
        guard let from = calendar.date(byAdding: .day, value: -7 * Self.startingVolumeWeeks, to: today) else {
            return Self.fallbackStartingVolume
        }
        let total = model.activities
            .filter { $0.sport == .running && $0.start >= from && $0.start < today }
            .reduce(0) { $0 + $1.duration }
        let weekly = total / Double(Self.startingVolumeWeeks)
        return weekly > 0 ? weekly : Self.fallbackStartingVolume
    }

    /// The weekly running time the athlete does now: the last two weeks averaged to 7 days, or `nil` when
    /// there is none. A conditioning phase builds up from it (MVP5-160).
    func currentVolume(asOf today: Date) -> TimeInterval? {
        guard let from = calendar.date(byAdding: .day, value: -7 * Self.currentVolumeWeeks, to: today) else { return nil }
        let total = model.activities
            .filter { $0.sport == .running && $0.start >= from && $0.start < today }
            .reduce(0) { $0 + $1.duration }
        return total > 0 ? total / Double(Self.currentVolumeWeeks) : nil
    }

    /// Asks the generator for a proposal from the current choices. Ignored while a generate or commit
    /// runs. A failure goes to ``failure`` and leaves no proposal.
    public func generate() async {
        guard !isBusy else { return }
        failure = nil
        guard let request = makeRequest() else {
            failure = CreatePlanStep.allCases.lazy.compactMap { self.problem(in: $0) }.first ?? "The plan can't be made from these choices."
            return
        }
        let inputs = currentInputs
        let generator = generator
        isGenerating = true
        defer { isGenerating = false }
        do {
            let made = try await generator(request)
            acceptsRisks = false
            // What activating would replace is read with the proposal, as of the same day. A failed read leaves the
            // proposal usable as a draft, but it can't be activated without knowing what it replaces.
            let today = calendar.startOfDay(for: now())
            var details: PlanPreviewDetails?
            var note: String?
            do {
                let preview = try await model.preview(made, asOf: today)
                let library = try await model.stores.workoutStore.workouts()
                details = PlanPreviewDetails(preview, library: library, calendar: calendar)
            } catch {
                note = "Couldn't check what the plan would replace: \(error.localizedDescription). You can still save it as a draft."
            }
            generated = (inputs, made, details, note)
        } catch is CancellationError {
            return
        } catch {
            generated = nil
            failure = Self.message(for: error)
        }
    }

    // MARK: Commit

    /// Stores the proposal as a plan: a draft, or with `activate` the active one (MVP5-121). Returns the stored plan once
    /// it is, and the wizard then closes. A second call while one runs, or after the plan exists, does nothing.
    ///
    /// Activating replaces the active plan as ``TrainingModel/commit(_:named:activate:acceptingRisks:asOf:)`` does (a followed
    /// plan is cancelled and kept, otherwise it becomes a draft; nothing is deleted) and is refused unless
    /// ``canActivate`` says it can be.
    ///
    /// - Parameters:
    ///   - activate: Whether to make the plan the active one; defaults to a draft. The risks are accepted as ``acceptsRisks`` says.
    @discardableResult
    public func commit(activate: Bool = false) async -> TrainingPlan? {
        guard !isBusy, committedPlan == nil, let proposal else { return nil }
        if activate, !canActivate {
            failure = proposal.isAcceptable ? "Couldn't check what the plan would replace, so it can't be activated." : "Accept the risks to activate this plan."
            return nil
        }
        let planName = effectiveName
        guard !planName.isEmpty else {
            failure = "A plan needs a name."
            return nil
        }
        let today = now()
        failure = nil
        isCommitting = true
        defer { isCommitting = false }
        do {
            let plan = try await model.commit(proposal, named: planName, activate: activate, acceptingRisks: acceptsRisks, asOf: today)
            committedPlan = plan
            return plan
        } catch {
            failure = "Couldn't save the plan: \(Self.message(for: error))"
            return nil
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case PlanGeneratorError.leadTime(.leadTimeTooShort(let available, let required)):
            return "There isn't enough time before the race: the plan needs at least \(required) micro-cycles and there \(available == 1 ? "is" : "are") \(available). Start earlier or choose a later race."
        case PlanGeneratorError.leadTime:
            return "The time between the start and the race can't be planned. Check the dates."
        case PlanGeneratorError.noLayout:
            return "The races and dates leave no room for a plan."
        case PlanGeneratorError.volumeCurve, PlanGeneratorError.unsupportedVolumeMeasure:
            return "The weekly volume can't be planned from these numbers. Check the peak volume."
        default:
            return error.localizedDescription
        }
    }
}

/// The full-length macro for a paradigm (MVP5-146): what ``PlanRequest/macro`` asks for, before the
/// generator's lead-time compromiser shortens it.
enum PlanMacro {
    /// - Parameters:
    ///   - paradigm: Decides the phases: triphasic (conditioning, base, structural, specific, taper) when it has a structural and a specific phase, else base, build, peak, taper.
    ///   - microLengthDays: The micro length; fixed phases are 42 days (structural, specific) or 21 days (peak) rounded to whole micros.
    ///   - leadTimeDays: The days from the start to race day, inclusive; base takes what the fixed phases leave.
    ///   - includeConditioning: Whether the triphasic conditioning phase leads the plan.
    static func template(
        for paradigm: TrainingParadigm, microLengthDays: Int, leadTimeDays: Int, includeConditioning: Bool
    ) -> MacroTemplate {
        let length = Double(max(microLengthDays, 1))
        func micros(_ days: Double) -> Int { max(Int((days / length).rounded()), 1) }
        let available = leadTimeDays / max(microLengthDays, 1)
        let isTriphasic = paradigm.phases.contains(.structural) && paradigm.phases.contains(.specific)
        var fixed: [MacroTemplate.MesoBlock]
        if isTriphasic {
            fixed = [.init(phase: .structural, microCount: micros(42)), .init(phase: .specific, microCount: micros(42)), .init(phase: .taper, microCount: 1)]
            if includeConditioning { fixed.insert(.init(phase: .conditioning, microCount: micros(42)), at: 0) }
        } else {
            fixed = [.init(phase: .build, microCount: micros(35)), .init(phase: .peak, microCount: micros(21)), .init(phase: .taper, microCount: 1)]
        }
        let base = max(available - fixed.reduce(0) { $0 + $1.microCount }, 0)
        var blocks = fixed
        if base > 0 {
            let at = blocks.first?.phase == .conditioning ? 1 : 0
            blocks.insert(.init(phase: .base, microCount: base), at: at)
        }
        return MacroTemplate(name: paradigm.name, mesoBlocks: blocks)
    }
}
