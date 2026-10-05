import Foundation

/// A push to a workout template's detail screen (MVP2-21), from the Library or search tab. A type
/// of its own rather than a bare `UUID`, so another UUID-keyed screen pushed onto the same stack
/// can't be routed here by mistake.
struct TemplateRoute: Hashable {
    /// The template's id; the detail reads its entry live from the library.
    let id: UUID
}
