import Foundation
import Testing
@testable import MealPrepPlanner

struct ProjectSmokeTests {
    @Test("New plan entries start unfinished")
    func newPlanEntryStartsUnprepared() {
        let meal = Meal(name: "Oats", ingredients: [])
        let entry = MealPlanEntry(meal: meal, scheduledDate: Date(), mealType: .breakfast)

        #expect(entry.isPrepared == false)
    }
}
