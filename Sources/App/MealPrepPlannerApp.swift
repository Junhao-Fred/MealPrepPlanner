//  Created by Junhao Huang on 2026/9/27.

import SwiftUI

@main
struct MealPrepPlannerApp: App {
    init() {
        Theme.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView { dependencies in
                RootTabView(repository: dependencies.repository, changes: dependencies.changes)
            }
        }
    }
}
