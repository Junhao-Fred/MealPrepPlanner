//  Created by Mingchen Liang on 2026/10/19.

import Foundation

/// Items and plan context from the same calculation, so the UI can explain an empty list.
struct ShoppingListSnapshot: Equatable, Sendable {
    let items: [ShoppingListItem]
    let plannedMealCount: Int
    let startDate: Date
    let endDate: Date
}

/// A positive purchase shortfall for one ingredient and unit.
struct ShoppingListItem: Identifiable, Equatable, Sendable {
    /// Matching follows `IngredientMatching`: plurals and convertible units share one ID.
    struct ID: Hashable, Sendable {
        let name: String
        let unit: String

        init(name: String, unit: String) {
            let key = IngredientMatching.key(name: name, unit: unit)
            self.name = key.name
            self.unit = key.unit
        }
    }

    let id: ID
    let name: String
    let quantity: Decimal
    let unit: String
}
