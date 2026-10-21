//  Created by Mingchen Liang on 2026/10/21.

import Foundation

enum MealEntryDraftError: Error, Equatable {
    case invalidQuantity(row: Int)
}

struct MealIngredientDraft: Identifiable {
    let id = UUID()
    var name = ""
    var quantityText = ""
    var unit = ""
}

/// Stable IDs let a failed submission retry the same plan, recipe and ingredient rows.
struct MealEntryDraft {
    let id = UUID()
    let mealID = UUID()
    var name = ""
    var mealType: MealType = .dinner
    var scheduledDate: Date
    var ingredients: [MealIngredientDraft] = [MealIngredientDraft()]

    func makeEntry(locale: Locale = .current) throws -> MealPlanEntry {
        let recipe = try ingredients.enumerated().map { index, row in
            guard let quantity = Self.parseQuantity(row.quantityText, locale: locale) else {
                throw MealEntryDraftError.invalidQuantity(row: index + 1)
            }
            return MealIngredient(
                id: row.id,
                name: row.name.trimmingCharacters(in: .whitespacesAndNewlines),
                quantity: quantity,
                unit: row.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return MealPlanEntry(
            id: id,
            meal: Meal(id: mealID, name: name.trimmingCharacters(in: .whitespacesAndNewlines), ingredients: recipe),
            scheduledDate: scheduledDate,
            mealType: mealType
        )
    }

    // Full-input parsing prevents Decimal(string:) from accepting a numeric prefix like "12g".
    private static func parseQuantity(_ text: String, locale: Locale) -> Decimal? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: locale.decimalSeparator ?? ".")
        guard parts.count <= 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let quantity = Decimal(string: parts.joined(separator: "."), locale: Locale(identifier: "en_US_POSIX")),
              !quantity.isNaN, quantity > 0 else { return nil }
        return quantity
    }
}
