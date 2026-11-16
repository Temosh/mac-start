import Foundation
import os

/// Where `PreferencesStore` keeps its value. `UserDefaults` in the app, an in-memory double in tests.
public protocol KeyValueStorage {
    func string(forKey key: String) -> String?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: KeyValueStorage {}

/// Keeps `Preferences` in `UserDefaults` as one JSON string under the key `preferences`, in the same format
/// as in export files.
public struct PreferencesStore {
    static let key = "preferences"

    private let storage: any KeyValueStorage
    private let logger = LogArea.layout.logger

    public init(storage: any KeyValueStorage = UserDefaults.standard) {
        self.storage = storage
    }

    /// The saved preferences, or nil when none were saved yet or the saved value cannot be read.
    public func load() -> Preferences? {
        guard let json = storage.string(forKey: Self.key) else {
            return nil
        }
        do {
            return try JSONFormat.decode(PreferencesRecord.self, from: Data(json.utf8)).preferences
        } catch {
            logger.error("Ignoring unreadable stored preferences: \(String(describing: error))")
            return nil
        }
    }

    public func save(_ preferences: Preferences) throws {
        let data = try JSONFormat.makeEncoder().encode(
            PreferencesRecord(schemaVersion: JSONFormat.schemaVersion, preferences: preferences)
        )
        storage.set(String(decoding: data, as: UTF8.self), forKey: Self.key)
    }
}

/// The stored preferences value.
private struct PreferencesRecord: Codable {
    let schemaVersion: Int
    let preferences: Preferences
}
