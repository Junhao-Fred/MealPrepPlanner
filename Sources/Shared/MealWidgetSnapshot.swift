//  Created by Junhao Huang on 2026/10/19.

import Foundation

/// The data the widget shows, written by the app so the extension never opens Core Data.
/// It stores raw times; the widget decides what is upcoming or expiring soon when it renders,
/// so the content stays right after midnight without the app running.
struct MealWidgetSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let useSoonDays = 3

    struct Meal: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let name: String
        let mealType: String
        let scheduledDate: Date
    }

    struct ExpiringIngredient: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let name: String
        let expiryDate: Date
    }

    var schemaVersion = Self.currentSchemaVersion
    var generatedAt: Date
    /// Unfinished meals, earliest first.
    var meals: [Meal]
    /// Available stock that has an expiry date, soonest first.
    var ingredients: [ExpiringIngredient]

    func upcomingMeals(at date: Date) -> [Meal] {
        meals.filter { $0.scheduledDate >= date }
    }

    func nextMeal(at date: Date) -> Meal? {
        upcomingMeals(at: date).first
    }

    func remainingMealsToday(at date: Date, calendar: Calendar) -> [Meal] {
        upcomingMeals(at: date).filter { calendar.isDate($0.scheduledDate, inSameDayAs: date) }
    }

    /// Same window as the app's expiry rule: expiry day in [today, today + 3 days).
    /// One entry per ingredient, so two batches of tomatoes count once.
    func useSoonIngredients(at date: Date, calendar: Calendar) -> [ExpiringIngredient] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: Self.useSoonDays, to: start) else {
            return []
        }
        var seen = Set<String>()
        return ingredients.filter { ingredient in
            let day = calendar.startOfDay(for: ingredient.expiryDate)
            return day >= start && day < end && seen.insert(IngredientMatching.normalizedName(ingredient.name)).inserted
        }
    }

    /// Ignores `generatedAt`, so rebuilding identical data does not reload the widget.
    func hasSameContent(as other: MealWidgetSnapshot) -> Bool {
        meals == other.meals && ingredients == other.ingredients
    }
}
