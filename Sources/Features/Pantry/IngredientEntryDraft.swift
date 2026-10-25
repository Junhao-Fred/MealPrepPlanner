//  Created by Mingchen Liang on 2026/10/20.

import Foundation

/// One form session keeps the same batch ID, including after a failed save.
struct IngredientEntryDraft {
    let id: UUID
    var name = ""
    var quantityText = ""
    var unit = ""
    var hasExpiryDate = false
    var expiryDate = Date()

    init() {
        id = UUID()
    }

    /// Prefills the form from a stored batch; saving updates that batch instead of adding one.
    init(editing ingredient: Ingredient, locale: Locale = .current) {
        id = ingredient.id
        name = ingredient.name
        quantityText = NSDecimalNumber(decimal: ingredient.quantity).description(withLocale: locale)
        unit = ingredient.unit
        hasExpiryDate = ingredient.expiryDate != nil
        expiryDate = ingredient.expiryDate ?? Date()
    }

    /// Name/unit validation remains in the save use case. Creating a draft never writes.
    func makeIngredient(locale: Locale = .current, calendar: Calendar = .current) throws -> Ingredient {
        guard let quantity = PantryQuantityParser.parse(quantityText, locale: locale) else {
            throw PantryError.invalidQuantity
        }
        return Ingredient(
            id: id,
            name: name,
            quantity: quantity,
            unit: unit,
            expiryDate: hasExpiryDate ? calendar.startOfDay(for: expiryDate) : nil
        )
    }
}
