import Foundation
import Observation
import TrainingCore
import TrainingWatchKit

/// Why a screen set can't be saved (WATCH-134).
public enum ScreenSetError: Error, Equatable {
    /// The set's name is empty.
    case emptyName
    /// The set has no screens.
    case noScreens
    /// The screen has no items.
    case emptyScreen(id: String)
    /// The screen's items take more than ``RunScreen/capacity`` units.
    case overCapacity(screenID: String)
    /// Two screens of the set share an id.
    case duplicateScreenID(String)
    /// The id belongs to a built-in set (`default.…`), which can't be replaced by an athlete's set.
    case reservedID
}

extension ScreenSetError {
    /// What to tell the athlete about a set that can't be saved.
    public var userMessage: String {
        switch self {
        case .emptyName: "Give the set a name."
        case .noScreens: "A set needs at least one screen."
        case .emptyScreen: "A screen needs at least one item. Add one or delete the screen."
        case .overCapacity: "A screen holds at most \(RunScreen.capacity) units. Remove an item."
        case .duplicateScreenID: "Two screens have the same identifier."
        case .reservedID: "That identifier belongs to a built-in set."
        }
    }
}

/// The athlete's run screens for the watch (WATCH-109, WATCH-134): the set for a free run, the one for a
/// workout and their own other sets, which a workout template can be linked to. Kept here in
/// `UserDefaults` and sent to the watch with the zones and the plan (``WatchSyncChannel``), which keeps
/// the last ones it got, like ``WatchCueSync``.
///
/// ``sync()`` sends the screens when the app becomes active, a change is sent at once. Deleting a set
/// removes the app's links to it; a custom template that names it still does, which is harmless: the
/// watch runs a workout with a set it doesn't have with the workout default. A change to a link asks
/// ``WatchPlanSync`` to send the plan again, since the plan carries each workout's set.
@MainActor
@Observable
public final class WatchScreenSetSync {
    /// The current screens; change them with the methods below.
    public private(set) var config: RunScreenConfig
    /// Counts the changes to the app's links for built-in templates, which `UserDefaults` doesn't announce: a view
    /// that reads ``linkedSetID(for:isCustom:)`` follows them through it.
    private var linksVersion = 0
    /// Why the screens couldn't be handed to the watch, or `nil`.
    public var lastError: String? { rejectedError ?? sender.lastSendError }

    @ObservationIgnored private let sender: any WatchSyncSending
    @ObservationIgnored private let cache: RunScreenCache
    @ObservationIgnored private let links: WatchScreenLinks
    @ObservationIgnored private let planSync: WatchPlanSync?
    @ObservationIgnored private var lastSent: RunScreenConfig?
    private var rejectedError: String?

    /// - Parameters:
    ///   - sender: What puts the screens on the watch.
    ///   - defaults: Where the screens are kept.
    ///   - links: The app's links from built-in templates to sets.
    ///   - planSync: Sends the plan again when a link changes; `nil` leaves that to the next send.
    public init(
        sender: any WatchSyncSending, defaults: UserDefaults = .standard,
        links: WatchScreenLinks? = nil, planSync: WatchPlanSync? = nil
    ) {
        self.sender = sender
        cache = RunScreenCache(defaults: defaults)
        self.links = links ?? WatchScreenLinks(defaults: defaults)
        self.planSync = planSync
        config = cache.load() ?? .default
    }

    /// Checks that `set` can be saved.
    ///
    /// - Throws: A ``ScreenSetError`` for the first problem found.
    public nonisolated static func validate(_ set: RunScreenSet) throws {
        guard !set.id.hasPrefix("default.") else { throw ScreenSetError.reservedID }
        guard !set.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ScreenSetError.emptyName }
        try validateScreens(set)
    }

    /// Checks the screens of `set`, not its name or id: what the built-in sets are held to.
    ///
    /// - Throws: A ``ScreenSetError`` for the first problem found.
    nonisolated static func validateScreens(_ set: RunScreenSet) throws {
        guard !set.screens.isEmpty else { throw ScreenSetError.noScreens }
        var seen = Set<String>()
        for screen in set.screens {
            guard seen.insert(screen.id).inserted else { throw ScreenSetError.duplicateScreenID(screen.id) }
            guard !screen.items.isEmpty else { throw ScreenSetError.emptyScreen(id: screen.id) }
            guard screen.fits else { throw ScreenSetError.overCapacity(screenID: screen.id) }
        }
    }

    /// A new, empty-named set with one screen of the standard metrics, ready to edit, with a fresh id.
    public static func newSet(named name: String) -> RunScreenSet {
        RunScreenSet(
            id: UUID().uuidString, name: name,
            screens: [RunScreen(id: UUID().uuidString, items: RunMetric.allCases.map(RunScreenItem.metric))])
    }

    /// Replaces the set for a free run (the built-in one's contents can be edited, its id stays).
    ///
    /// - Throws: A ``ScreenSetError`` when the screens aren't valid.
    public func updateFreeRun(_ set: RunScreenSet) throws {
        try Self.validateScreens(set)
        var config = config
        config.freeRun = RunScreenSet(id: RunScreenSet.freeRunDefault.id, name: set.name, screens: set.screens, startScreenID: set.startScreenID)
        apply(config)
    }

    /// Replaces the set for a workout that has no set of its own.
    ///
    /// - Throws: A ``ScreenSetError`` when the screens aren't valid.
    public func updateWorkout(_ set: RunScreenSet) throws {
        try Self.validateScreens(set)
        var config = config
        config.workout = RunScreenSet(id: RunScreenSet.workoutDefault.id, name: set.name, screens: set.screens, startScreenID: set.startScreenID)
        apply(config)
    }

    /// Adds `set` or replaces the one with its id.
    ///
    /// - Throws: A ``ScreenSetError`` when the set isn't valid.
    public func save(_ set: RunScreenSet) throws {
        try Self.validate(set)
        var config = config
        if let index = config.sets.firstIndex(where: { $0.id == set.id }) {
            config.sets[index] = set
        } else {
            config.sets.append(set)
        }
        apply(config)
    }

    /// Deletes the set and the app's links to it. A workout linked to it runs with the workout default.
    public func deleteSet(id: String) {
        var config = config
        config.sets.removeAll { $0.id == id }
        links.removeLinks(to: id)
        linksVersion += 1
        apply(config)
        replanAfterLinkChange()
    }

    /// Goes back to the built-in screens and removes every custom set and the app's links to them.
    public func resetToDefaults() {
        for set in config.sets { links.removeLinks(to: set.id) }
        linksVersion += 1
        apply(.default)
        replanAfterLinkChange()
    }

    /// Links a built-in template to `setID`, or unlinks it with `nil`; the plan is sent again. A custom
    /// template carries its own link (`WorkoutTemplate/watchScreenSetID`), which the template's own
    /// store saves.
    public func link(builtInTemplate template: UUID, to setID: String?) {
        links.link(template: template, to: setID)
        linksVersion += 1
        replanAfterLinkChange()
    }

    /// The set a workout template is linked to: its own `watchScreenSetID` for a custom template, the app's link
    /// for a built-in one; `nil` for the workout default.
    public func linkedSetID(for template: WorkoutTemplate, isCustom: Bool) -> String? {
        _ = linksVersion
        return isCustom ? template.watchScreenSetID : links.setID(forTemplate: template.id)
    }

    /// Links `template` to the set `setID`, or unlinks it with `nil`, and sends the plan again. A custom template is
    /// saved with the id; a built-in one can't change, so the app keeps the link.
    ///
    /// - Throws: What saving the custom template throws; nothing changes then.
    public func link(_ template: WorkoutTemplate, isCustom: Bool, to setID: String?, model: TrainingModel) async throws {
        if isCustom {
            var template = template
            template.watchScreenSetID = setID
            try await model.add(template)
            await planSync?.sync()
        } else {
            link(builtInTemplate: template.id, to: setID)
        }
    }

    /// Sends the screens if they weren't sent yet in this run of the app, or changed since.
    public func sync() {
        guard config != lastSent else { return }
        do {
            try sender.send(screens: config)
            lastSent = config
            rejectedError = nil
        } catch {
            rejectedError = error.localizedDescription
        }
    }

    private func apply(_ config: RunScreenConfig) {
        self.config = config
        cache.save(config)
        sync()
    }

    private func replanAfterLinkChange() {
        guard let planSync else { return }
        Task { await planSync.sync() }
    }
}
