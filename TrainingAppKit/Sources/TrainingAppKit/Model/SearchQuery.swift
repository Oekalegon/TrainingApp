import Foundation

/// What the athlete typed in the tab bar's search field (MVP2-21), split into words. A set of
/// fields matches when every word appears in one of them, ignoring case and diacritics, so
/// "long km" finds "20 km Long Run".
struct SearchQuery: Equatable, Sendable {
    /// The typed words, in order; empty for a blank field.
    let words: [String]

    init(_ text: String) {
        words = text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// `true` for a blank field, which matches everything.
    var isEmpty: Bool { words.isEmpty }

    /// Whether every word appears in at least one of `fields`.
    func matches(_ fields: [String]) -> Bool {
        words.allSatisfy { word in fields.contains { $0.localizedStandardContains(word) } }
    }
}
