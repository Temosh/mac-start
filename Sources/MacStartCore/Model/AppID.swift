import Foundation

/// The identity of one app bundle on disk: its standardized path, plus its bundle identifier when it has one.
///
/// Two `AppID`s are equal when their paths are equal. Every bundle on disk is a separate app, even when several
/// bundles share one bundle identifier. The bundle identifier only lets reconcile follow an app that moved.
public struct AppID: Sendable {
    /// The absolute path of the `.app` bundle, standardized and without a trailing slash.
    public let path: String
    /// The bundle's `CFBundleIdentifier`, if it has one.
    public let bundleIdentifier: String?

    public init(path: String, bundleIdentifier: String?) {
        self.path = Self.standardizedPath(path)
        self.bundleIdentifier = bundleIdentifier
    }

    /// Resolves `.` and `..` components and removes trailing slashes. Symbolic links are kept as they are.
    static func standardizedPath(_ path: String) -> String {
        var standardized = URL(filePath: path, directoryHint: .notDirectory).standardized.path(percentEncoded: false)
        while standardized.count > 1, standardized.hasSuffix("/") {
            standardized.removeLast()
        }
        return standardized
    }
}

extension AppID: Hashable {
    public static func == (lhs: AppID, rhs: AppID) -> Bool {
        lhs.path == rhs.path
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}

extension AppID: Codable {
    private enum CodingKeys: String, CodingKey {
        case path
        case bundleIdentifier
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let path = try container.decode(String.self, forKey: .path)
        guard path.hasPrefix("/") else {
            throw DecodingError.dataCorruptedError(
                forKey: .path,
                in: container,
                debugDescription: "An app path must be absolute, got \"\(path)\"."
            )
        }
        self.init(path: path, bundleIdentifier: try container.decodeIfPresent(String.self, forKey: .bundleIdentifier))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(bundleIdentifier, forKey: .bundleIdentifier)
    }
}
