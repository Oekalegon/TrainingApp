import Foundation

/// A map in the library (MVP4-101): a store file copied into the app, or a folder of blocks (or a very big file) the app links
/// to and leaves where it is.
public struct MapItem: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// One `.gmk` file, held in the app's own folder.
        case file
        /// A folder with a `manifest.json` and block files: it stays where it is, as it can be several gigabytes.
        case blocks
        /// One `.gmk` file too big to copy (see ``MapLibrary/copyLimit``): it stays where it is.
        case linkedFile
    }

    /// The name of the file in the library, with its extension: unique, and what the selection is stored as.
    public let id: String
    /// What the athlete sees: the file name without its extension.
    public var name: String
    public let kind: Kind
    /// The size of the file, or `nil` for a linked folder.
    public var bytes: Int64?
    public var date: Date

    public init(id: String, name: String, kind: Kind, bytes: Int64?, date: Date) {
        self.id = id
        self.name = name
        self.kind = kind
        self.bytes = bytes
        self.date = date
    }
}
