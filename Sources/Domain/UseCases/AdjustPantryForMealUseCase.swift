//  Created by Junhao Huang on 2026/10/23.

import Foundation

/// Moves a recipe's quantities out of pantry stock when a meal is prepared, and back in when that is undone.
/// Batches are saved one at a time, so callers must serialize changes to the same pantry.
struct AdjustPantryForMealUseCase: Sendable {
    /// Part of a recipe the pantry could not cover, in the recipe's own unit.
    struct Shortfall: Equatable, Sendable {
        let name: String
        let quantity: Decimal
        let unit: String
    }

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

    /// Uses valid batches that expire first. Missing stock is reported, never treated as an error.
    @discardableResult
    func deduct(_ meal: Meal) async throws -> [Shortfall] {
        let start = calendar.startOfDay(for: now())
        let stock = try await repository.fetchAvailableIngredients()
        var shortfalls: [Shortfall] = []

        for need in requirements(of: meal) {
            let batches = stock
                .filter { IngredientMatching.key(name: $0.name, unit: $0.unit) == need.key }
                .filter { $0.expiryDate.map { $0 >= start } ?? true }
                .sorted { ($0.expiryDate ?? .distantFuture, $0.id.uuidString) < ($1.expiryDate ?? .distantFuture, $1.id.uuidString) }

            var remaining = need.amount
            for var batch in batches where remaining > 0 {
                let available = IngredientMatching.baseQuantity(batch.quantity, unit: batch.unit)
                let used = min(available, remaining)
                batch.quantity = IngredientMatching.quantity(fromBase: available - used, unit: batch.unit)
                try await repository.saveIngredient(batch)
                remaining -= used
            }
            if remaining > 0 {
                shortfalls.append(Shortfall(
                    name: need.name,
                    quantity: IngredientMatching.quantity(fromBase: remaining, unit: need.unit),
                    unit: need.unit
                ))
            }
        }
        return shortfalls
    }

    /// Adds the recipe back into the matching batch that expires last, or as a new undated batch.
    func restore(_ meal: Meal) async throws {
        let stock = try await repository.fetchAvailableIngredients()

        for need in requirements(of: meal) {
            let target = stock
                .filter { IngredientMatching.key(name: $0.name, unit: $0.unit) == need.key }
                .max { ($0.expiryDate ?? .distantFuture, $0.id.uuidString) < ($1.expiryDate ?? .distantFuture, $1.id.uuidString) }

            if var batch = target {
                let current = IngredientMatching.baseQuantity(batch.quantity, unit: batch.unit)
                batch.quantity = IngredientMatching.quantity(fromBase: current + need.amount, unit: batch.unit)
                try await repository.saveIngredient(batch)
            } else {
                try await repository.saveIngredient(Ingredient(
                    name: need.name,
                    quantity: IngredientMatching.quantity(fromBase: need.amount, unit: need.unit),
                    unit: need.unit
                ))
            }
        }
    }

    private struct Requirement {
        let key: IngredientMatching.Key
        let name: String
        let unit: String
        var amount: Decimal
    }

    /// Combines recipe lines that match, keeping the first line's name and unit for display.
    private func requirements(of meal: Meal) -> [Requirement] {
        var result: [Requirement] = []
        for ingredient in meal.ingredients where ingredient.quantity > 0 {
            let key = IngredientMatching.key(name: ingredient.name, unit: ingredient.unit)
            let amount = IngredientMatching.baseQuantity(ingredient.quantity, unit: ingredient.unit)
            if let index = result.firstIndex(where: { $0.key == key }) {
                result[index].amount += amount
            } else {
                result.append(Requirement(key: key, name: ingredient.name, unit: ingredient.unit, amount: amount))
            }
        }
        return result
    }
}
