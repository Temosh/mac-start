/// One grid slot: an app or a folder.
public enum Item: Hashable, Sendable {
    case app(AppID)
    case folder(Folder)

    /// The apps in this slot, in display order: one for an app, the folder's apps for a folder.
    public var appIDs: [AppID] {
        switch self {
        case .app(let id): [id]
        case .folder(let folder): folder.apps
        }
    }
}

extension Item: Codable {
    // Encoded as a single-key object, `{"app": {...}}` or `{"folder": {...}}`, so files stay readable.
    private enum CodingKeys: String, CodingKey {
        case app
        case folder
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch (container.contains(.app), container.contains(.folder)) {
        case (true, false):
            self = .app(try container.decode(AppID.self, forKey: .app))
        case (false, true):
            self = .folder(try container.decode(Folder.self, forKey: .folder))
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "An item must hold exactly one of \"app\" or \"folder\"."
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let id): try container.encode(id, forKey: .app)
        case .folder(let folder): try container.encode(folder, forKey: .folder)
        }
    }
}
