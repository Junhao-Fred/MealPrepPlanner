//  Created by Junhao Huang on 2026/10/19.

import Foundation
import Observation

/// Composition root. Builds the live repository once and hands it to every screen through the environment:
/// `@Environment(AppDependencies.self) private var dependencies`.
@MainActor @Observable
final class AppDependencies {
    /// Use this for all reads and writes; each successful write refreshes the widget and bumps `changes`.
    let repository: any MealPlanningRepository
    let changes: DataChangeTracker

    @ObservationIgnored private let snapshotRefresher: WidgetSnapshotRefresher

    init(
        repository base: any MealPlanningRepository,
        makeSnapshotRefresher: (any MealPlanningRepository) -> WidgetSnapshotRefresher = {
            WidgetSnapshotRefresher(repository: $0)
        }
    ) {
        let changes = DataChangeTracker()
        let refresher = makeSnapshotRefresher(base)
        self.changes = changes
        self.snapshotRefresher = refresher
        self.repository = WidgetRefreshingRepository(wrapping: base) {
            await changes.recordChange()
            Task { await refresher.refresh() }
        }
    }

    /// Opens the on-disk Core Data store. Throws when the store cannot be loaded, so the app can offer a retry.
    static func live() async throws -> AppDependencies {
        let persistence = try await PersistenceController.makePersistent()
        return AppDependencies(repository: CoreDataMealRepository(container: persistence.container))
    }

    func refreshWidgetSnapshot() async {
        await snapshotRefresher.refresh()
    }
}
