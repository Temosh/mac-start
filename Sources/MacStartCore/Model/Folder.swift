import Foundation

/// A named group of apps that occupies one grid slot.
public struct Folder: Hashable, Sendable, Codable, Identifiable {
    /// Stays the same for the folder's whole life, across renames, moves, exports, and imports.
    public let id: UUID
    public var name: String
    /// The folder's apps in display order.
    public var apps: [AppID]

    public init(id: UUID = UUID(), name: String, apps: [AppID]) {
        self.id = id
        self.name = name
        self.apps = apps
    }
}
