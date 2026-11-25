import Foundation

/// Which run screen set the athlete linked to which built-in workout template (WATCH-133): a sprint
/// interval session gets other screens than a long run. A custom template carries its own link
/// (`WorkoutTemplate.watchScreenSetID`, which wins); the built-in templates are constants and can't, so their
/// links are kept here, in `UserDefaults`, by the template's id. A workout made from a template with a link is
/// sent to the watch with the set's id (``WatchPlanSync``), and one with none runs with the workout default.
///
/// The editor that sets the links is WATCH-134, which also sends the sets themselves. A link to a set that
/// no longer exists is harmless: the watch falls back to the default.
public struct WatchScreenLinks: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let key = "watchScreenLinks.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var links: [String: String] {
        get { defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }

    /// The set linked to `template`, or `nil` for the workout default or a workout with no template.
    public func setID(forTemplate template: UUID?) -> String? {
        template.flatMap { links[$0.uuidString] }
    }

    /// Links `template` to the set `setID`, or removes the link when `setID` is `nil`.
    public func link(template: UUID, to setID: String?) {
        var links = links
        links[template.uuidString] = setID
        self.links = links
    }

    /// The templates linked to `setID`, for the set's editor.
    public func templates(linkedTo setID: String) -> [UUID] {
        links.filter { $0.value == setID }.compactMap { UUID(uuidString: $0.key) }
    }

    /// Removes every link to `setID`, when the set is deleted.
    public func removeLinks(to setID: String) {
        links = links.filter { $0.value != setID }
    }
}
