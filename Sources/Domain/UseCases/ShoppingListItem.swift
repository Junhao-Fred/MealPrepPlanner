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
    /// Matching ignores whitespace and case; units are never converted.
    struct ID: Hashable, Sendable {
        let name: String
        let unit: String

        init(name: String, unit: String) {
            self.name = name.filter { !$0.isWhitespace }.lowercased()
            self.unit = unit.filter { !$0.isWhitespace }.lowercased()
        }
    }

    let id: ID
    let name: String
    let quantity: Decimal
    let unit: String
}
