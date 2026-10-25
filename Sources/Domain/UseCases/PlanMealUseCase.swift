//  Created by Junhao Huang on 2026/9/27.

import Foundation

enum MealPlanningValidationError: Error, Equatable, Sendable {
    case emptyMealName
    case emptyIngredients
    case invalidIngredient
    /// Scheduled before today. Earlier today is allowed, so a meal can be logged after it happened.
    case scheduledInThePast
}

/// Validates and atomically saves a scheduled meal.
struct PlanMealUseCase: Sendable {
    private let repository: any MealPlanningRepository
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        repository: any MealPlanningRepository,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.calendar = calendar
        self.now = now
    }

    /// Throws a validation or repository error when saving fails.
    func execute(_ entry: MealPlanEntry) async throws {
        guard !entry.meal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MealPlanningValidationError.emptyMealName
        }
        guard !entry.meal.ingredients.isEmpty else {
            throw MealPlanningValidationError.emptyIngredients
        }
        guard entry.meal.ingredients.allSatisfy({ ingredient in
            !ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            ingredient.quantity > 0
        }) else {
            throw MealPlanningValidationError.invalidIngredient
        }
        guard entry.scheduledDate >= calendar.startOfDay(for: now()) else {
            throw MealPlanningValidationError.scheduledInThePast
        }

        try await repository.savePlannedMeal(entry)
    }
}
