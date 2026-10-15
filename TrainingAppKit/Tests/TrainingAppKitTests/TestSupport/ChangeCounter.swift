/// Counts calls to an `onPlansChanged` callback. A main-actor class rather than a captured `var`, so
/// the `@MainActor` closure that increments it stays `Sendable`.
@MainActor
final class ChangeCounter {
    var count = 0
}
