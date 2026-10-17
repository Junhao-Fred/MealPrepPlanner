//  Created by Junhao Huang on 2026/9/27.

import Foundation

/// An ingredient amount required for one meal preparation.
struct MealIngredient: Identifiable, Codable, Equatable, Sendable {
    let id: UUID

    var name: String

    var quantity: Decimal

    var unit: String

    init(id: UUID = UUID(), name: String, quantity: Decimal, unit: String) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
    }
}
