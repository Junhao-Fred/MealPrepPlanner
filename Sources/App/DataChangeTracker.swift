//  Created by Junhao Huang on 2026/10/19.

import Observation

/// Bumps `version` after every successful repository write.
/// Screens reload with `.task(id: changes.version)` so Today, Plan, Pantry and Shopping stay in step.
@MainActor @Observable
final class DataChangeTracker {
    private(set) var version = 0

    func recordChange() {
        version += 1
    }
}
