//  Created by Junhao Huang on 2026/10/23.

import Foundation
import Testing
@testable import MealPrepPlanner

@MainActor
@Suite("Same ingredient counted once")
struct PantryGroupingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Plural names and repeat purchases form one item, soonest expiry first, named by the shortest spelling")
    func groupsSameIngredient() {
        let undated = Ingredient(name: "Tomatoes", quantity: 200, unit: "g")
        let soon = Ingredient(name: "Tomato", quantity: 150, unit: "g", expiryDate: now)
        let rice = Ingredient(name: "Rice", quantity: 1, unit: "kg")

        let groups = PantryItemGroup.group([undated, rice, soon])

        #expect(groups.map(\.name) == ["Rice", "Tomato"])
        let tomato = groups[1]
        #expect(tomato.quantity == 350)
        #expect(tomato.unit == "g")
        #expect(tomato.batches == [soon, undated])
        #expect(tomato.earliestExpiry == now)
    }

    @Test("Mixed but convertible units are totalled; unrelated units stay separate")
    func mixedUnits() {
        let groups = PantryItemGroup.group([
            Ingredient(name: "Rice", quantity: 1, unit: "kg"),
            Ingredient(name: "Rice", quantity: 200, unit: "g"),
            Ingredient(name: "Rice", quantity: 2, unit: "bag")
        ])

        #expect(groups.count == 2)
        #expect(groups.contains { $0.quantity == Decimal(string: "1.2")! && $0.unit == "kg" })
        #expect(groups.contains { $0.quantity == 2 && $0.unit == "bag" })
    }

    @Test("Using an item deducts across batches, soonest expiry first, in the item's unit")
    func useAcrossBatches() async throws {
        let soon = Ingredient(name: "Rice", quantity: 300, unit: "g", expiryDate: now)
        let later = Ingredient(name: "Rice", quantity: 1, unit: "kg", expiryDate: now.addingTimeInterval(9 * 86_400))
        let repository = InMemoryMealRepository(ingredients: [soon, later])
        let group = try #require(PantryItemGroup.group([soon, later]).first)
        #expect(group.unit == "kg")

        try await UsePantryItemUseCase(repository: repository)
            .execute(batchIDs: group.batches.map(\.id), quantity: Decimal(string: "0.5")!, unit: group.unit)

        let stock = try await repository.fetchAvailableIngredients()
        #expect(stock.map(\.id) == [later.id])
        #expect(stock.first?.quantity == Decimal(string: "0.8")!)
    }

    @Test("Using more than the whole item is rejected without changing any batch")
    func useTooMuch() async throws {
        let first = Ingredient(name: "Egg", quantity: 2, unit: "piece")
        let second = Ingredient(name: "Eggs", quantity: 3, unit: "pcs")
        let repository = InMemoryMealRepository(ingredients: [first, second])

        await #expect(throws: PantryError.insufficientIngredient) {
            try await UsePantryItemUseCase(repository: repository).execute(batchIDs: [first.id, second.id], quantity: 6, unit: "piece")
        }
        let writes = await repository.writeCount
        #expect(writes == 0)
    }

    @Test("The pantry view model uses and deletes a whole item")
    func viewModelGroupActions() async throws {
        let tomato = Ingredient(name: "Tomato", quantity: 200, unit: "g", expiryDate: now)
        let tomatoes = Ingredient(name: "Tomatoes", quantity: 200, unit: "g")
        let rice = Ingredient(name: "Rice", quantity: 1, unit: "kg")
        let repository = InMemoryMealRepository(ingredients: [tomato, tomatoes, rice])
        let model = PantryViewModel(repository: repository)
        await model.load()
        #expect(model.groups.count == 2)

        let group = try #require(model.groups.first { $0.name == "Tomato" })
        #expect(await model.use(group, quantity: 250))
        let used = try #require(model.groups.first { $0.name == "Tomatoes" })
        #expect(used.quantity == 150)
        #expect(used.batches.count == 1)

        #expect(await model.deleteGroup(used))
        #expect(model.groups.map(\.name) == ["Rice"])
        #expect(!model.isBusy)
    }

    @Test("The widget counts two batches of one ingredient once")
    func widgetCountsOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let snapshot = MealWidgetSnapshot(
            generatedAt: now,
            meals: [],
            ingredients: [
                .init(id: UUID(), name: "Tomato", expiryDate: now),
                .init(id: UUID(), name: "Tomatoes", expiryDate: now.addingTimeInterval(86_400)),
                .init(id: UUID(), name: "Milk", expiryDate: now)
            ]
        )

        #expect(snapshot.useSoonIngredients(at: now, calendar: calendar).map(\.name) == ["Tomato", "Milk"])
    }
}
