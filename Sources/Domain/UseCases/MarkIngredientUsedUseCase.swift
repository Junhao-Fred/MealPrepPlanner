//  Created by Mingchen Liang on 2026/10/19.

import Foundation

/// Deducts an explicitly entered quantity from a stored pantry batch.
struct MarkIngredientUsedUseCase: Sendable {
    private let repository: any MealPlanningRepository

    init(repository: any MealPlanningRepository) {
        self.repository = repository
    }

    /// Returns the updated batch only after saving succeeds.
    /// A missing or depleted batch reports `ingredientNotFound`.
    /// Callers must serialize mutations to the same batch: the repository's
    /// separate read and save operations do not provide an atomic deduction.
    @discardableResult
    func execute(ingredientID: UUID, quantity: Decimal) async throws -> Ingredient {
        guard !quantity.isNaN, quantity > 0 else {
            throw PantryError.invalidQuantity
        }

        let ingredients = try await repository.fetchAvailableIngredients()
        guard var ingredient = ingredients.first(where: { $0.id == ingredientID }) else {
            throw PantryError.ingredientNotFound
        }
        guard quantity <= ingredient.quantity else {
            throw PantryError.insufficientIngredient
        }

        ingredient.quantity -= quantity
        try await repository.saveIngredient(ingredient)
        return ingredient
    }
}
