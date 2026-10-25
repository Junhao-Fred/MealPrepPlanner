//  Created by Junhao Huang on 2026/10/23.

import Foundation

/// Deducts an entered amount from all batches of one ingredient, soonest expiry first.
struct UsePantryItemUseCase: Sendable {
    private let repository: any MealPlanningRepository

    init(repository: any MealPlanningRepository) {
        self.repository = repository
    }

    /// `quantity` is in `unit`, which may differ from the batches' units when they convert.
    /// Rereads stock first, so a stale group cannot over-deduct; returns the saved batches.
    @discardableResult
    func execute(batchIDs: [UUID], quantity: Decimal, unit: String) async throws -> [Ingredient] {
        guard !quantity.isNaN, quantity > 0 else {
            throw PantryError.invalidQuantity
        }
        let ids = Set(batchIDs)
        let batches = try await repository.fetchAvailableIngredients()
            .filter { ids.contains($0.id) }
            .sorted(by: PantryItemGroup.soonestFirst)
        guard !batches.isEmpty else {
            throw PantryError.ingredientNotFound
        }

        var remaining = IngredientMatching.baseQuantity(quantity, unit: unit)
        let available = batches.reduce(Decimal(0)) { $0 + IngredientMatching.baseQuantity($1.quantity, unit: $1.unit) }
        guard remaining <= available else {
            throw PantryError.insufficientIngredient
        }

        var saved: [Ingredient] = []
        for var batch in batches where remaining > 0 {
            let stock = IngredientMatching.baseQuantity(batch.quantity, unit: batch.unit)
            let used = min(stock, remaining)
            batch.quantity = IngredientMatching.quantity(fromBase: stock - used, unit: batch.unit)
            try await repository.saveIngredient(batch)
            saved.append(batch)
            remaining -= used
        }
        return saved
    }
}
