//  Created by Junhao Huang on 2026/9/27.

import Foundation

/// A reusable meal recipe.
struct Meal: Identifiable, Codable, Equatable, Sendable {
    let id: UUID

    var name: String

    var ingredients: [MealIngredient]

    init(id: UUID = UUID(), name: String, ingredients: [MealIngredient]) {
        self.id = id
        self.name = name
        self.ingredients = ingredients
    }
}
