//  Created by Junhao Huang on 2026/10/19.

#if DEBUG
import Foundation

extension AppDependencies {
    static let previewSnapshotSuite = "MealPrepPlannerPreviews"

    /// Dependencies for SwiftUI previews: `.environment(AppDependencies.preview())`.
    /// Pass `InMemoryMealRepository()` for an empty state. Never touches the real App Group or reloads widgets.
    static func preview(
        repository: any MealPlanningRepository = InMemoryMealRepository.preview()
    ) -> AppDependencies {
        AppDependencies(repository: repository) {
            WidgetSnapshotRefresher(
                repository: $0,
                store: WidgetSnapshotStore(suiteName: previewSnapshotSuite),
                reloadTimelines: {}
            )
        }
    }
}
#endif
