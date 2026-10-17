//  Created by Junhao Huang on 2026/9/27.

import Foundation

enum MealPlanningValidationError: Error, Equatable, Sendable {
    case emptyMealName
    case emptyIngredients
    case invalidIngredient
    case scheduledInThePast
}

/// Validates and atomically saves a scheduled meal.
struct PlanMealUseCase: Sendable {
    private let repository: any MealPlanningRepository
    private let now: @Sendable () -> Date

    init(
        repository: any MealPlanningRepository,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
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
        guard entry.scheduledDate >= now() else {
            throw MealPlanningValidationError.scheduledInThePast
        }

        try await repository.savePlannedMeal(entry)
    }
}
