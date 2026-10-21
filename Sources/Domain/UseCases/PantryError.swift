//  Created by Mingchen Liang on 2026/10/19.

/// Invalid pantry input or a stock operation that cannot be completed.
/// Storage failures remain `RepositoryError` values from the repository.
enum PantryError: Error, Equatable, Sendable {
    case emptyIngredientName
    case emptyUnit
    case invalidQuantity
    case ingredientNotFound
    case insufficientIngredient
}
