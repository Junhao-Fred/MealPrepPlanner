//  Created by Junhao Huang on 2026/10/22.

import Foundation
import os
import Testing
@testable import MealPrepPlanner

@MainActor
@Suite("Pantry batch deletion")
struct PantryDeleteTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Use case

    @Test("Deleting removes only the selected batch")
    func deleteRemovesSelectedBatch() async throws {
        let tomato = Ingredient(name: "Tomato", quantity: 200, unit: "g")
        let rice = Ingredient(name: "Rice", quantity: 1, unit: "kg")
        let repository = InMemoryMealRepository(ingredients: [tomato, rice])

        try await DeletePantryIngredientUseCase(repository: repository).execute(ingredientID: tomato.id)

        let available = try await repository.fetchAvailableIngredients()
        let writeCount = await repository.writeCount
        #expect(available == [rice])
        #expect(writeCount == 1)
    }

    @Test("Deleting a missing batch reports ingredientNotFound without writing")
    func deleteMissingBatch() async {
        let repository = InMemoryMealRepository(ingredients: [Ingredient(name: "Rice", quantity: 1, unit: "kg")])

        await #expect(throws: PantryError.ingredientNotFound) {
            try await DeletePantryIngredientUseCase(repository: repository).execute(ingredientID: UUID())
        }
        let writeCount = await repository.writeCount
        #expect(writeCount == 0)
    }

    @Test("A failed delete propagates the repository error and keeps the batch")
    func deleteWriteFailureKeepsStock() async throws {
        let tomato = Ingredient(name: "Tomato", quantity: 200, unit: "g")
        let repository = InMemoryMealRepository(ingredients: [tomato])
        await repository.fail(.write, with: .writeFailed)

        await #expect(throws: RepositoryError.writeFailed) {
            try await DeletePantryIngredientUseCase(repository: repository).execute(ingredientID: tomato.id)
        }

        await repository.clearFailures()
        let available = try await repository.fetchAvailableIngredients()
        #expect(available == [tomato])
    }

    // MARK: View model

    @Test("Deleting from the view model drops the card and releases busy state")
    func viewModelDelete() async {
        let tomato = Ingredient(name: "Tomato", quantity: 200, unit: "g")
        let rice = Ingredient(name: "Rice", quantity: 1, unit: "kg")
        let model = PantryViewModel(repository: InMemoryMealRepository(ingredients: [tomato, rice]))
        await model.load()

        let deleted = await model.deleteIngredient(id: tomato.id)

        #expect(deleted)
        #expect(model.ingredients == [rice])
        #expect(model.errorMessage == nil)
        #expect(model.deletingIngredientID == nil)
        #expect(!model.isBusy)
    }

    @Test("A failed delete returns false and keeps the displayed list")
    func viewModelDeleteFailure() async {
        let tomato = Ingredient(name: "Tomato", quantity: 200, unit: "g")
        let repository = InMemoryMealRepository(ingredients: [tomato])
        let model = PantryViewModel(repository: repository)
        await model.load()
        await repository.fail(.write, with: .writeFailed)

        let deleted = await model.deleteIngredient(id: tomato.id)

        #expect(!deleted)
        #expect(model.ingredients == [tomato])
        #expect(model.errorMessage == "Unable to save your pantry changes. Please try again.")
        #expect(!model.isBusy)
    }

    @Test("A delete followed by a failed refresh still hides the batch and asks for a reload")
    func viewModelDeleteThenRefreshFailure() async {
        let tomato = Ingredient(name: "Tomato", quantity: 200, unit: "g")
        let repository = InMemoryMealRepository(ingredients: [tomato])
        let model = PantryViewModel(repository: repository)
        await model.load()
        await repository.fail(.read, with: .readFailed)

        let deleted = await model.deleteIngredient(id: tomato.id)

        #expect(deleted)
        #expect(model.ingredients.isEmpty)
        #expect(model.needsReload)
        #expect(model.errorMessage?.hasPrefix("Ingredient deleted.") == true)
    }

    // MARK: Other features

    @Test("A successful delete reaches the widget refresh; a failed one does not")
    func deleteReportsWrite() async throws {
        let tomato = Ingredient(name: "Tomato", quantity: 200, unit: "g")
        let base = InMemoryMealRepository(ingredients: [tomato])
        let writes = OSAllocatedUnfairLock(initialState: 0)
        let repository = WidgetRefreshingRepository(wrapping: base) { writes.withLock { $0 += 1 } }

        await #expect(throws: RepositoryError.notFound) {
            try await repository.deleteIngredient(id: UUID())
        }
        #expect(writes.withLock { $0 } == 0)

        try await repository.deleteIngredient(id: tomato.id)
        #expect(writes.withLock { $0 } == 1)
    }

    @Test("Deleted stock no longer covers planned meals on the shopping list")
    func deleteUpdatesShoppingList() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = now
        let entry = MealPlanEntry(
            meal: Meal(name: "Pasta", ingredients: [MealIngredient(name: "Tomato", quantity: 300, unit: "g")]),
            scheduledDate: date.addingTimeInterval(3_600),
            mealType: .dinner
        )
        let tomato = Ingredient(name: "Tomato", quantity: 200, unit: "g")
        let repository = InMemoryMealRepository(entries: [entry], ingredients: [tomato], now: { date })
        let shopping = GenerateShoppingListUseCase(repository: repository, calendar: calendar, now: { date })

        let before = try await shopping.execute()
        try await DeletePantryIngredientUseCase(repository: repository).execute(ingredientID: tomato.id)
        let after = try await shopping.execute()

        #expect(before.map(\.quantity) == [100])
        #expect(after.map(\.quantity) == [300])
    }
}
