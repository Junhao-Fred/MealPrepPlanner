import Foundation
import Testing
@testable import MealPrepPlanner

struct ProjectSmokeTests {
    @Test("The app exposes the four required feature tabs")
    func requiredFeatureTabsAreConfigured() {
        #expect(AppTab.allCases.map(\.title) == [
            "Today",
            "Meal Plan",
            "Pantry",
            "Shopping List"
        ])
        #expect(Set(AppTab.allCases.map(\.systemImage)).count == 4)
    }

    @Test("New plan entries start unfinished")
    func newPlanEntryStartsUnprepared() {
        let meal = Meal(name: "Oats", ingredients: [])
        let entry = MealPlanEntry(meal: meal, scheduledDate: Date(), mealType: .breakfast)

        #expect(entry.isPrepared == false)
    }
}
