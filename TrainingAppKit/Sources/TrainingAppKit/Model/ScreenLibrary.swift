import Foundation
import TrainingWatchKit

/// The screens the athlete can add to a set from the Add Screen sheet: the standard screens
/// (``StandardScreens``) and the athlete's own, the screens already in their sets, and the search over both.
public enum ScreenLibrary {
    /// The athlete's own screens: those in the free-run set, the workout set and their own sets, each once (a screen
    /// that two sets share, or that only differs in its id, is listed once) and without the ones that are just a
    /// standard screen, which the sheet lists under the standard screens.
    /// - Parameters:
    ///   - config: The saved sets.
    ///   - editing: The screens of the set being edited, saved or not: a screen made in it is offered at once, before
    ///     the set is saved.
    public static func userScreens(in config: RunScreenConfig, editing: [RunScreen] = []) -> [RunScreen] {
        var seen: [RunScreen] = []
        let standardItems = StandardScreens.all.map(\.items)
        for screen in ([config.freeRun, config.workout] + config.sets).flatMap(\.screens) + editing {
            let isStandard = standardItems.contains(screen.items) && (screen.name ?? "").isEmpty
            let isKnown = seen.contains { $0.items == screen.items && $0.name == screen.name }
            if !isStandard && !isKnown { seen.append(screen) }
        }
        return seen
    }

    /// Whether a screen with this name and these items answers a search: the text is in the name, or in the title of
    /// any item (so "current pace" finds every screen that shows the current pace). Case and accents don't matter, and
    /// an empty search matches everything.
    public static func matches(name: String?, items: [RunScreenItem], query: String) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return ([name ?? ""] + items.map(\.title)).contains { $0.range(of: text, options: options) != nil }
    }
}

extension RunScreenSetDraft {
    /// Adds a copy of a screen the athlete already has (in another set, say) with the same items and name, under a new
    /// id so the two can be changed apart.
    /// - Returns: The new screen's id.
    @discardableResult
    public mutating func addScreen(copying screen: RunScreen) -> String {
        let copy = RunScreen(id: UUID().uuidString, items: screen.items, name: screen.name)
        screens.append(copy)
        return copy.id
    }
}
