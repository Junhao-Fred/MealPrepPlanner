//  Created by Mingchen Liang on 2026/10/19.

import Foundation

/// Validates and saves a pantry batch, preserving its ID and optional expiry.
struct SavePantryIngredientUseCase: Sendable {
    private let repository: any MealPlanningRepository

    init(repository: any MealPlanningRepository) {
        self.repository = repository
    }

    /// Trims surrounding whitespace and requires a positive quantity.
    /// Use `MarkIngredientUsedUseCase` to consume stock down to zero.
    func execute(_ ingredient: Ingredient) async throws {
        var validatedIngredient = ingredient
        validatedIngredient.name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
        validatedIngredient.unit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !validatedIngredient.name.isEmpty else {
            throw PantryError.emptyIngredientName
        }
        guard !validatedIngredient.unit.isEmpty else {
            throw PantryError.emptyUnit
        }
        guard !validatedIngredient.quantity.isNaN, validatedIngredient.quantity > 0 else {
            throw PantryError.invalidQuantity
        }

        try await repository.saveIngredient(validatedIngredient)
    }
}
