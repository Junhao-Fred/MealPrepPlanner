//  Created by Junhao Huang on 2026/10/19.

#if DEBUG
import Foundation

/// A sample week relative to `now` for SwiftUI previews. Debug builds only.
/// It covers every state the screens show: a prepared breakfast, lunch and dinner today, meals on later days,
/// stock expiring today and within three days, expired stock and stock without an expiry date.
/// The two tomato meals need 300 g and 250 g against 200 g in stock, so the shopping list shows 350 g.
enum PreviewData {
    static func entries(now: Date = Date(), calendar: Calendar = .current) -> [MealPlanEntry] {
        let at = dateMaker(now: now, calendar: calendar)
        return [
            MealPlanEntry(
                meal: Meal(name: "Berry Oats", ingredients: [
                    MealIngredient(name: "Oats", quantity: 80, unit: "g"),
                    MealIngredient(name: "Milk", quantity: 200, unit: "ml")
                ]),
                scheduledDate: at(0, 8, 0),
                mealType: .breakfast,
                isPrepared: true
            ),
            MealPlanEntry(
                meal: Meal(name: "Chicken Rice Bowl", ingredients: [
                    MealIngredient(name: "Chicken breast", quantity: 250, unit: "g"),
                    MealIngredient(name: "Rice", quantity: 150, unit: "g")
                ]),
                scheduledDate: at(0, 12, 30),
                mealType: .lunch
            ),
            MealPlanEntry(
                meal: Meal(name: "Tomato Pasta", ingredients: [
                    MealIngredient(name: "Tomato", quantity: 300, unit: "g"),
                    MealIngredient(name: "Pasta", quantity: 200, unit: "g")
                ]),
                scheduledDate: at(0, 19, 0),
                mealType: .dinner
            ),
            MealPlanEntry(
                meal: Meal(name: "Tomato Salad", ingredients: [
                    MealIngredient(name: "Tomato", quantity: 250, unit: "g"),
                    MealIngredient(name: "Spinach", quantity: 50, unit: "g")
                ]),
                scheduledDate: at(1, 12, 30),
                mealType: .lunch
            ),
            MealPlanEntry(
                meal: Meal(name: "Chicken Curry", ingredients: [
                    MealIngredient(name: "Chicken breast", quantity: 300, unit: "g"),
                    MealIngredient(name: "Rice", quantity: 150, unit: "g")
                ]),
                scheduledDate: at(2, 19, 0),
                mealType: .dinner
            )
        ]
    }

    static func ingredients(now: Date = Date(), calendar: Calendar = .current) -> [Ingredient] {
        let at = dateMaker(now: now, calendar: calendar)
        return [
            Ingredient(name: "Milk", quantity: 800, unit: "ml", expiryDate: at(0, 0, 0)),
            Ingredient(name: "Chicken breast", quantity: 500, unit: "g", expiryDate: at(1, 0, 0)),
            Ingredient(name: "Tomato", quantity: 200, unit: "g", expiryDate: at(2, 0, 0)),
            Ingredient(name: "Eggs", quantity: 6, unit: "pcs", expiryDate: at(5, 0, 0)),
            Ingredient(name: "Spinach", quantity: 150, unit: "g", expiryDate: at(-1, 0, 0)),
            Ingredient(name: "Rice", quantity: 1000, unit: "g")
        ]
    }

    private static func dateMaker(now: Date, calendar: Calendar) -> (Int, Int, Int) -> Date {
        let today = calendar.startOfDay(for: now)
        return { day, hour, minute in
            calendar.date(byAdding: DateComponents(day: day, hour: hour, minute: minute), to: today)!
        }
    }
}

extension InMemoryMealRepository {
    /// A repository filled with `PreviewData`. Use `InMemoryMealRepository()` for empty states.
    static func preview(now: Date = Date(), calendar: Calendar = .current) -> InMemoryMealRepository {
        InMemoryMealRepository(
            entries: PreviewData.entries(now: now, calendar: calendar),
            ingredients: PreviewData.ingredients(now: now, calendar: calendar),
            now: { now }
        )
    }
}
#endif
