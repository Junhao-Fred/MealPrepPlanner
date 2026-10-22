//  Created by Junhao Huang on 2026/10/23.

import Foundation
import Testing
@testable import MealPrepPlanner

@Suite("Ingredient matching")
struct IngredientMatchingTests {
    @Test("Plural names match their singular", arguments: [
        ("Tomatoes", "tomato"), ("Berries", "berry"), ("Eggs", "egg"),
        ("Peaches", "peach"), ("Cherry Tomatoes", "cherrytomato"), ("Rice", "rice")
    ])
    func pluralNames(name: String, expected: String) {
        #expect(IngredientMatching.normalizedName(name) == expected)
    }

    @Test("Words ending in ss, us or is are not shortened", arguments: ["Glass", "Asparagus", "Hummus", "Pastis"])
    func protectedEndings(name: String) {
        #expect(IngredientMatching.normalizedName(name) == name.lowercased())
    }

    @Test("Mass, volume and count units share a key and convert to it")
    func unitConversion() {
        #expect(IngredientMatching.key(name: "Rice", unit: "kg") == IngredientMatching.key(name: "rice", unit: " G "))
        #expect(IngredientMatching.key(name: "Milk", unit: "L") == IngredientMatching.key(name: "milk", unit: "ml"))
        #expect(IngredientMatching.key(name: "Egg", unit: "pcs") == IngredientMatching.key(name: "eggs", unit: "piece"))
        #expect(IngredientMatching.baseQuantity(Decimal(string: "1.5")!, unit: "kg") == 1_500)
        #expect(IngredientMatching.baseQuantity(2, unit: "tbsp") == 30)
        #expect(IngredientMatching.quantity(fromBase: 800, unit: "kg") == Decimal(string: "0.8")!)
    }

    @Test("Unknown units match only themselves, ignoring plurals")
    func unknownUnits() {
        #expect(IngredientMatching.key(name: "Beans", unit: "cans") == IngredientMatching.key(name: "beans", unit: "can"))
        #expect(IngredientMatching.key(name: "Rice", unit: "bag") != IngredientMatching.key(name: "Rice", unit: "g"))
        #expect(IngredientMatching.baseQuantity(3, unit: "can") == 3)
    }

    @Test("Shopping list shows kg once a converted total reaches 1000 g")
    func shoppingListScalesLargeTotals() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = MealPlanEntry(
            meal: Meal(name: "Risotto", ingredients: [MealIngredient(name: "Rice", quantity: Decimal(string: "1.5")!, unit: "kg")]),
            scheduledDate: now.addingTimeInterval(3_600),
            mealType: .dinner
        )
        let repository = InMemoryMealRepository(
            entries: [entry],
            ingredients: [Ingredient(name: "rice", quantity: 300, unit: "g")],
            now: { now }
        )

        let result = try await GenerateShoppingListUseCase(repository: repository, now: { now }).execute()

        #expect(result.map(\.quantity) == [Decimal(string: "1.2")!])
        #expect(result.map(\.unit) == ["kg"])
    }
}
