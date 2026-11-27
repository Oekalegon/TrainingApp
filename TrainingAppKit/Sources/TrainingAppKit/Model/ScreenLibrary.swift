import Foundation
import TrainingWatchKit

/// The screens the athlete can add to a set from the Add Screen sheet: the standard screens
/// (``StandardScreens``) and the athlete's own, the screens already in their sets, and the search over both.
public enum ScreenLibrary {
    /// The athlete's own screens: those in the free-run set, the workout set, their own sets and the set being edited,
    /// each once (a screen that two sets share, or that only differs in its id, is listed once). A screen that comes
    /// with the app is not theirs: one with the items of a standard screen or of a default screen and no name, or the
    /// name the app gave it, is listed under the standard screens, or not at all (the defaults). A screen they named
    /// or changed is theirs.
    /// - Parameters:
    ///   - config: The saved sets.
    ///   - editing: The screens of the set being edited, saved or not: a screen made in it is offered at once, before
    ///     the set is saved.
    public static func userScreens(in config: RunScreenConfig, editing: [RunScreen] = []) -> [RunScreen] {
        var seen: [RunScreen] = []
        for screen in ([config.freeRun, config.workout] + config.sets).flatMap(\.screens) + editing {
            let isKnown = seen.contains { $0.items == screen.items && $0.name == screen.name }
            if !comesWithApp(screen) && !isKnown { seen.append(screen) }
        }
        return seen
    }

    /// Whether a screen is one the app supplies: the items of a standard screen or of a factory default screen, with no
    /// name or the standard screen's own title, or an unnamed blank screen.
    static func comesWithApp(_ screen: RunScreen) -> Bool {
        let name = screen.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let standard = StandardScreens.all.contains { $0.items == screen.items && (name.isEmpty || name == $0.title) }
        let defaults = (RunScreenSet.freeRunDefault.screens + RunScreenSet.workoutDefault.screens).contains { $0.items == screen.items }
        // An unchanged blank screen is what Blank Screen already offers.
        let blank = screen.items == [.metric(.totalTime)] && name.isEmpty
        return standard || (defaults && name.isEmpty) || blank
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
