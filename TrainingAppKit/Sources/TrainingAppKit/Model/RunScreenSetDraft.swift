import Foundation
import TrainingWatchKit

/// A run screen set while the athlete edits it (WATCH-134): the changes are made on this copy and only
/// handed to ``WatchScreenSetSync`` when the athlete saves, so a half-made set never reaches the watch.
/// All the rules of a screen live here, so they are tested and the views stay thin: a screen holds at most
/// ``RunScreen/capacity`` units, so an item that doesn't fit isn't added, and the screens can be reordered: the run
/// opens on the first one.
public struct RunScreenSetDraft: Equatable, Sendable {
    public var id: String
    public var name: String
    public var screens: [RunScreen]
    /// The id of the screen the run opens on; always nil in a draft, which opens on the first screen (an older set
    /// that named another one has it moved to the front when the draft is made).
    public var startScreenID: String?

    public init(_ set: RunScreenSet) {
        id = set.id
        name = set.name
        // The run opens on the first screen, so a screen an older set opened on goes to the front: saving the set
        // doesn't change where the run opens.
        var screens = set.screens
        if let start = set.startScreenID, let index = screens.firstIndex(where: { $0.id == start }), index > 0 {
            screens.insert(screens.remove(at: index), at: 0)
        }
        self.screens = screens
        startScreenID = nil
    }

    /// The set the draft stands for.
    public var set: RunScreenSet {
        // A name of only spaces is no name.
        let named = screens.map { screen -> RunScreen in
            var screen = screen
            let trimmed = screen.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            screen.name = trimmed?.isEmpty == false ? trimmed : nil
            return screen
        }
        return RunScreenSet(id: id, name: name, screens: named, startScreenID: startScreenID)
    }

    /// The first problem that keeps the set from being saved, or `nil`. The name only counts for the
    /// athlete's own sets: the two built-in ones keep their names.
    public func validationError(checksName: Bool = true) -> ScreenSetError? {
        do {
            if checksName { try WatchScreenSetSync.validate(set) } else { try WatchScreenSetSync.validateScreens(set) }
            return nil
        } catch {
            return error as? ScreenSetError
        }
    }

    /// Whether screen `screenID` holds an item that means something only in a planned workout's steps, so the
    /// whole screen is left out of a free run (and of a workout once its steps are used up).
    public func isOnlyInWorkouts(_ screenID: String) -> Bool {
        screens.first { $0.id == screenID }?.requiresSteps ?? false
    }

    /// The units the items of screen `screenID` take; 0 for an unknown screen.
    public func units(of screenID: String) -> Int {
        screens.first { $0.id == screenID }?.units ?? 0
    }

    /// Whether `item` fits in what is left of screen `screenID`.
    public func canAdd(_ item: RunScreenItem, to screenID: String) -> Bool {
        guard let screen = screens.first(where: { $0.id == screenID }) else { return false }
        return screen.units + item.height <= RunScreen.capacity
    }

    /// Adds `item` at the end of screen `screenID` (the bottom of the screen, where the most important item belongs).
    ///
    /// - Returns: `false`, with nothing changed, when it doesn't fit.
    @discardableResult
    public mutating func add(_ item: RunScreenItem, to screenID: String) -> Bool {
        guard canAdd(item, to: screenID), let index = screens.firstIndex(where: { $0.id == screenID }) else { return false }
        screens[index].items.append(item)
        return true
    }

    /// Removes the items at `offsets` from screen `screenID`.
    public mutating func removeItems(at offsets: IndexSet, from screenID: String) {
        guard let index = screens.firstIndex(where: { $0.id == screenID }) else { return }
        screens[index].items.remove(atOffsets: offsets)
    }

    /// Moves items within screen `screenID`, as a `List`'s `onMove` does.
    public mutating func moveItems(from source: IndexSet, to destination: Int, in screenID: String) {
        guard let index = screens.firstIndex(where: { $0.id == screenID }) else { return }
        screens[index].items.move(fromOffsets: source, toOffset: destination)
    }

    /// Whether a screen has all the room a watch offers (`units`: 6 on an Ultra, 5 on the others), so no item can be
    /// added for that watch. The athlete's choice of watch in the preview decides which.
    public func isFull(_ screenID: String, fittingUnits units: Int) -> Bool {
        self.units(of: screenID) >= units
    }

    /// The name of a screen as the list shows it: nil when it has none, or only spaces.
    public func displayName(of screenID: String) -> String? {
        let name = screens.first { $0.id == screenID }?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }

    /// Adds a screen with the total time on it (a screen can't be empty) and returns its id.
    @discardableResult
    public mutating func addScreen() -> String {
        let screen = RunScreen(id: UUID().uuidString, items: [.metric(.totalTime)])
        screens.append(screen)
        return screen.id
    }

    /// Removes the screens at `offsets`, but never the last one: a set holds at least one screen. A start
    /// screen that goes is forgotten, so the run opens on the first.
    public mutating func removeScreens(at offsets: IndexSet) {
        var remaining = screens
        remaining.remove(atOffsets: offsets)
        guard !remaining.isEmpty else { return }
        screens = remaining
        if let startScreenID, !screens.contains(where: { $0.id == startScreenID }) { self.startScreenID = nil }
    }

    /// Moves screens, as a `List`'s `onMove` does.
    public mutating func moveScreens(from source: IndexSet, to destination: Int) {
        screens.move(fromOffsets: source, toOffset: destination)
    }

    /// The screen the run opens on.
    public var startScreen: RunScreen? {
        startScreenID.flatMap { id in screens.first { $0.id == id } } ?? screens.first
    }
}
