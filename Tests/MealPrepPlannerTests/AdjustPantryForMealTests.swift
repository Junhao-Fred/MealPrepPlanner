//  Created by Junhao Huang on 2026/10/23.

import Foundation
import Testing
@testable import MealPrepPlanner

@MainActor
@Suite("Pantry stock follows prepared meals")
struct AdjustPantryForMealTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    @Test("Deduction uses the batch that expires first, converts units and skips expired stock")
    func deductsEarliestBatchFirst() async throws {
        let expired = Ingredient(name: "Rice", quantity: 1, unit: "kg", expiryDate: now.addingTimeInterval(-3 * 86_400))
        let soon = Ingredient(name: "Rice", quantity: Decimal(string: "0.2")!, unit: "kg", expiryDate: now.addingTimeInterval(86_400))
        let later = Ingredient(name: "rice", quantity: 500, unit: "g", expiryDate: now.addingTimeInterval(9 * 86_400))
        let repository = InMemoryMealRepository(ingredients: [expired, soon, later])

        let shortfalls = try await makeAdjuster(repository).deduct(meal(("Rice", 300, "g")))

        #expect(shortfalls.isEmpty)
        let stock = try await repository.fetchAvailableIngredients()
        #expect(Set(stock.map(\.id)) == [expired.id, later.id])
        #expect(stock.first { $0.id == later.id }?.quantity == 400)
        #expect(stock.first { $0.id == expired.id }?.quantity == 1)
    }

    @Test("Plural pantry names are used, and missing stock is reported in the recipe's unit")
    func reportsShortfall() async throws {
        let tomatoes = Ingredient(name: "Tomatoes", quantity: 200, unit: "g")
        let repository = InMemoryMealRepository(ingredients: [tomatoes])

        let shortfalls = try await makeAdjuster(repository).deduct(meal(("Tomato", 300, "g"), ("Basil", 1, "bunch")))

        #expect(shortfalls == [
            .init(name: "Tomato", quantity: 100, unit: "g"),
            .init(name: "Basil", quantity: 1, unit: "bunch")
        ])
        let stock = try await repository.fetchAvailableIngredients()
        #expect(stock.isEmpty)
    }

    @Test("Restoring adds back to the batch that expires last, or creates an undated batch")
    func restoresStock() async throws {
        let rice = Ingredient(name: "Rice", quantity: 1, unit: "kg", expiryDate: now.addingTimeInterval(86_400))
        let repository = InMemoryMealRepository(ingredients: [rice])

        try await makeAdjuster(repository).restore(meal(("Rice", 250, "g"), ("Milk", 200, "ml")))

        let stock = try await repository.fetchAvailableIngredients()
        #expect(stock.first { $0.id == rice.id }?.quantity == Decimal(string: "1.25")!)
        let milk = stock.first { $0.name == "Milk" }
        #expect(milk?.quantity == 200)
        #expect(milk?.unit == "ml")
        #expect(milk?.expiryDate == nil)
    }

    @Test("Preparing then undoing with ingredients returned leaves stock as it was")
    func prepareAndUndoRoundTrip() async throws {
        let rice = Ingredient(name: "Rice", quantity: 500, unit: "g")
        let entry = MealPlanEntry(meal: meal(("Rice", 200, "g")), scheduledDate: now, mealType: .dinner)
        let repository = InMemoryMealRepository(entries: [entry], ingredients: [rice])
        let useCase = MarkMealPreparedUseCase(repository: repository, calendar: calendar, now: { now })

        _ = try await useCase.prepare(id: entry.id)
        #expect(try await repository.fetchAvailableIngredients().map(\.quantity) == [300])

        let undone = try await useCase.undo(id: entry.id, returningIngredients: true)
        #expect(!undone.isPrepared)
        #expect(try await repository.fetchAvailableIngredients().map(\.quantity) == [500])
    }

    @Test("Undoing without returning ingredients only changes the meal")
    func undoKeepsStock() async throws {
        let rice = Ingredient(name: "Rice", quantity: 300, unit: "g")
        var entry = MealPlanEntry(meal: meal(("Rice", 200, "g")), scheduledDate: now, mealType: .dinner)
        entry.isPrepared = true
        let repository = InMemoryMealRepository(entries: [entry], ingredients: [rice])

        let undone = try await MarkMealPreparedUseCase(repository: repository).undo(id: entry.id, returningIngredients: false)

        #expect(!undone.isPrepared)
        #expect(try await repository.fetchAvailableIngredients() == [rice])
    }

    @Test("After one meal is prepared, its used stock no longer covers the next meal on the shopping list")
    func shoppingListStaysAccurate() async throws {
        let tomato = Ingredient(name: "Tomato", quantity: 200, unit: "g")
        let monday = MealPlanEntry(meal: meal(("Tomato", 200, "g")), scheduledDate: now.addingTimeInterval(3_600), mealType: .lunch)
        let wednesday = MealPlanEntry(meal: meal(("Tomato", 200, "g")), scheduledDate: now.addingTimeInterval(2 * 86_400), mealType: .dinner)
        let repository = InMemoryMealRepository(entries: [monday, wednesday], ingredients: [tomato], now: { now })
        let shopping = GenerateShoppingListUseCase(repository: repository, calendar: calendar, now: { now })

        #expect(try await shopping.execute().map(\.quantity) == [200])
        _ = try await MarkMealPreparedUseCase(repository: repository, calendar: calendar, now: { now }).prepare(id: monday.id)

        #expect(try await shopping.execute().map(\.quantity) == [200])
    }

    @Test("Meal details explain a shortfall and can undo")
    func detailViewModel() async {
        let entry = MealPlanEntry(meal: meal(("Tomato", 300, "g")), scheduledDate: now, mealType: .dinner)
        let repository = InMemoryMealRepository(entries: [entry], ingredients: [Ingredient(name: "Tomato", quantity: 200, unit: "g")])
        let model = MealDetailViewModel(id: entry.id, useCase: MarkMealPreparedUseCase(repository: repository))
        await model.load()

        #expect(await model.markPrepared())
        #expect(model.entry?.isPrepared == true)
        #expect(model.notice?.contains("100 g Tomato") == true)

        #expect(await model.undoPrepared(returningIngredients: true))
        #expect(model.entry?.isPrepared == false)
        #expect(model.errorMessage == nil)
    }

    @Test("Meal details can delete the meal")
    func detailViewModelDelete() async throws {
        let entry = MealPlanEntry(meal: meal(("Tomato", 300, "g")), scheduledDate: now, mealType: .dinner)
        let repository = InMemoryMealRepository(entries: [entry])
        let model = MealDetailViewModel(
            id: entry.id,
            useCase: MarkMealPreparedUseCase(repository: repository),
            deleteUseCase: DeleteMealPlanEntryUseCase(repository: repository)
        )
        await model.load()

        #expect(await model.delete())
        let remaining = try await repository.fetchMealPlanEntries(from: .distantPast, to: .distantFuture, includingPrepared: true)
        #expect(remaining.isEmpty)
    }

    private func makeAdjuster(_ repository: InMemoryMealRepository) -> AdjustPantryForMealUseCase {
        let date = now
        return AdjustPantryForMealUseCase(repository: repository, calendar: calendar, now: { date })
    }

    private func meal(_ lines: (String, Decimal, String)...) -> Meal {
        Meal(name: "Meal", ingredients: lines.map { MealIngredient(name: $0.0, quantity: $0.1, unit: $0.2) })
    }
}
