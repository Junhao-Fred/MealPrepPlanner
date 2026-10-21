//  Created by Junhao Huang on 2026/10/19.

import Foundation

enum WidgetSnapshotStoreError: Error, Equatable, Sendable {
    case groupUnavailable
}

/// Reads and writes the widget snapshot in the App Group's shared defaults.
struct WidgetSnapshotStore: Sendable {
    private struct SchemaHeader: Decodable {
        let schemaVersion: Int
    }

    private let suiteName: String
    private let key: String

    init(
        suiteName: String = AppGroupConfiguration.identifier,
        key: String = AppGroupConfiguration.snapshotKey
    ) {
        self.suiteName = suiteName
        self.key = key
    }

    /// Returns nil when nothing is saved, the data is unreadable or another schema version wrote it.
    func load() -> MealWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(SchemaHeader.self, from: data),
              header.schemaVersion == MealWidgetSnapshot.currentSchemaVersion else {
            return nil
        }
        return try? decoder.decode(MealWidgetSnapshot.self, from: data)
    }

    func save(_ snapshot: MealWidgetSnapshot) throws {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw WidgetSnapshotStoreError.groupUnavailable
        }
        defaults.set(try JSONEncoder().encode(snapshot), forKey: key)
    }
}
