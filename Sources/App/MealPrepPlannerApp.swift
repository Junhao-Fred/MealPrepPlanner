//  Created by Junhao Huang on 2026/9/27.

import SwiftUI

@main
struct MealPrepPlannerApp: App {
    #if DEBUG
    private let repository = InMemoryMealRepository.preview()
    #endif

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            RootTabView(repository: repository)
            #else
            RootTabView()
            #endif
        }
    }
}
