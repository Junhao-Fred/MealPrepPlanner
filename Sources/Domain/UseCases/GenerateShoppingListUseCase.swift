//  Created by Mingchen Liang on 2026/10/19.

import Foundation

enum ShoppingListError: Error, Equatable, Sendable {
    case invalidDateRange
    case invalidIngredient
    case quantityOverflow
}

/// Calculates purchase shortfalls without changing meal plans or pantry stock.
struct GenerateShoppingListUseCase: Sendable {
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

    /// Includes unfinished plans in [today's midnight, seven calendar days later).
    /// Stock is valid through its expiry day; undated stock is also available.
    /// Repository failures propagate unchanged, rather than producing a partial list.
    func execute() async throws -> [ShoppingListItem] {
        try await executeSnapshot().items
    }

    /// Includes the unfinished plan count and exact range used for this calculation.
    func executeSnapshot() async throws -> ShoppingListSnapshot {
        let start = calendar.startOfDay(for: now())
        guard let end = calendar.date(byAdding: .day, value: 7, to: start), end > start else {
            throw ShoppingListError.invalidDateRange
        }

        let entries = try await repository.fetchMealPlanEntries(
            from: start, to: end, includingPrepared: false
        )
        var demand: [ShoppingListItem.ID: Demand] = [:]
        for entry in entries {
            // Each scheduled preparation contributes its recipe, even when recipes share an ID.
            for ingredient in entry.meal.ingredients {
                let key = ShoppingListItem.ID(name: ingredient.name, unit: ingredient.unit)
                guard !key.name.isEmpty, !key.unit.isEmpty,
                      !ingredient.quantity.isNaN, ingredient.quantity > 0 else {
                    throw ShoppingListError.invalidIngredient
                }

                let total = try adding(demand[key]?.quantity ?? 0, ingredient.quantity)
                var combined = demand[key] ?? Demand(
                    name: displayText(ingredient.name),
                    unit: displayText(ingredient.unit),
                    quantity: 0
                )
                combined.quantity = total
                demand[key] = combined
            }
        }
        guard !demand.isEmpty else {
            return ShoppingListSnapshot(items: [], plannedMealCount: entries.count, startDate: start, endDate: end)
        }

        let ingredients = try await repository.fetchAvailableIngredients()
        var stock: [ShoppingListItem.ID: Decimal] = [:]
        for ingredient in ingredients {
            if let expiry = ingredient.expiryDate, expiry < start { continue }
            let key = ShoppingListItem.ID(name: ingredient.name, unit: ingredient.unit)
            guard demand[key] != nil else { continue }
            guard !ingredient.quantity.isNaN, ingredient.quantity >= 0 else {
                throw ShoppingListError.invalidIngredient
            }
            stock[key] = try adding(stock[key] ?? 0, ingredient.quantity)
        }

        var result: [ShoppingListItem] = []
        for (key, required) in demand {
            // Deduct the combined stock once, after all meal requirements are summed.
            let shortfall = max(required.quantity - (stock[key] ?? 0), 0)
            guard shortfall > 0 else { continue }
            result.append(ShoppingListItem(
                id: key, name: required.name, quantity: shortfall, unit: required.unit
            ))
        }
        return ShoppingListSnapshot(
            items: result.sorted { ($0.id.name, $0.id.unit) < ($1.id.name, $1.id.unit) },
            plannedMealCount: entries.count,
            startDate: start,
            endDate: end
        )
    }

    private struct Demand {
        let name: String
        let unit: String
        var quantity: Decimal
    }

    private func adding(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        let total = lhs + rhs
        guard !total.isNaN else { throw ShoppingListError.quantityOverflow }
        return total
    }

    private func displayText(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
