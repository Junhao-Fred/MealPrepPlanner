import SwiftUI

@main
struct MealPrepPlannerApp: App {
    private let repository: any MealPlanningRepository = MockMealPlanningRepository.demo()

    var body: some Scene {
        WindowGroup {
            RootTabView(repository: repository)
        }
    }
}
