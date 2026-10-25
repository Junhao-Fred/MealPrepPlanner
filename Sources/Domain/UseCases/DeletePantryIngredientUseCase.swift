//  Created by Junhao Huang on 2026/10/22.

import Foundation

/// Removes a pantry batch entirely, for stock entered by mistake or thrown away.
struct DeletePantryIngredientUseCase: Sendable {
    private let repository: any MealPlanningRepository

    init(repository: any MealPlanningRepository) {
        self.repository = repository
    }

    /// A batch that is already gone reports `ingredientNotFound`, matching stock deductions.
    func execute(ingredientID: UUID) async throws {
        do {
            try await repository.deleteIngredient(id: ingredientID)
        } catch RepositoryError.notFound {
            throw PantryError.ingredientNotFound
        }
    }
}
