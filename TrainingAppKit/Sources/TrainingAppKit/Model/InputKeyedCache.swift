import Foundation

/// A cache of one value per id that reuses an entry only while the inputs it was computed from are
/// unchanged.
///
/// The day list re-renders on every touch-move frame of the week-swipe drag, so anything a card
/// derives from an activity or plan has to be cached — but a cache keyed only on an id (or on
/// collection counts) goes stale when an item is edited in place: a plan's load override, a
/// workout's parameters, an activity's link. Each entry here remembers the `inputs` it was computed
/// from and is recomputed when they differ.
struct InputKeyedCache<Value> {
    private var entries: [UUID: (inputs: [Int], value: Value)] = [:]

    /// The number of cached entries.
    var count: Int { entries.count }

    /// The cached value for `id` if it was computed from `inputs`, else `compute()`'s, which is then
    /// cached.
    ///
    /// - Parameters:
    ///   - id: The activity or plan the value belongs to.
    ///   - inputs: Hashes of everything the value depends on beyond `id`.
    ///   - compute: Produces the value when there is no current entry.
    mutating func value(for id: UUID, inputs: [Int], compute: () -> Value) -> Value {
        if let entry = entries[id], entry.inputs == inputs {
            return entry.value
        }
        let value = compute()
        entries[id] = (inputs, value)
        return value
    }

    /// Drops every entry.
    mutating func removeAll() {
        entries.removeAll()
    }

    /// Drops the entries of ids that are no longer loaded, so deleted activities and plans don't
    /// linger.
    mutating func retain(_ ids: Set<UUID>) {
        entries = entries.filter { ids.contains($0.key) }
    }
}
