//  Created by Mingchen Liang on 2026/10/21.

import Foundation
import Testing
@testable import MealPrepPlanner

@MainActor
@Suite("Shopping list loading and empty states")
struct ShoppingListViewModelTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 21))!
    }

    @Test("An empty plan has a successful snapshot with zero unfinished meals")
    func noPlans() async throws {
        let model = makeModel(InMemoryMealRepository())

        await model.load()

        let result = try #require(model.snapshot)
        #expect(result.items.isEmpty)
        #expect(result.plannedMealCount == 0)
        #expect(result.startDate == today)
        #expect(result.endDate == calendar.date(byAdding: .day, value: 7, to: today))
        #expect(model.errorMessage == nil)
        #expect(!model.isLoading)
    }

    @Test("Covered demand is distinguishable from having no plans")
    func nothingToBuy() async throws {
        let repository = InMemoryMealRepository(
            entries: [makeEntry()],
            ingredients: [Ingredient(name: "Rice", quantity: 100, unit: "g")]
        )
        let model = makeModel(repository)

        await model.load()

        let result = try #require(model.snapshot)
        #expect(result.items.isEmpty)
        #expect(result.plannedMealCount == 1)
        #expect(model.errorMessage == nil)
    }

    @Test("The snapshot counts only unfinished plans within its range")
    func countsEligiblePlansAndDisplaysGap() async throws {
        var prepared = makeEntry()
        prepared.isPrepared = true
        var outside = makeEntry()
        outside.scheduledDate = calendar.date(byAdding: .day, value: 7, to: today)!
        let repository = InMemoryMealRepository(entries: [makeEntry(), prepared, outside])
        let model = makeModel(repository)

        await model.load()

        let result = try #require(model.snapshot)
        #expect(result.plannedMealCount == 1)
        #expect(result.items == [ShoppingListItem(id: .init(name: "Rice", unit: "g"), name: "Rice", quantity: 100, unit: "g")])
        let writes = await repository.writeCount
        #expect(writes == 0)
    }

    @Test("Read failures remain errors, retry recovers and later failures preserve the prior snapshot")
    func failedLoadAndRetry() async throws {
        let repository = InMemoryMealRepository(entries: [makeEntry()])
        let model = makeModel(repository)
        await repository.fail(.read, with: .readFailed)

        await model.load()
        #expect(model.snapshot == nil)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)

        await repository.clearFailures()
        await model.load()
        let previous = try #require(model.snapshot)
        #expect(model.errorMessage == nil)

        await repository.fail(.read, with: .storeUnavailable)
        await model.load()
        #expect(model.snapshot == previous)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)
    }

    @Test("Refreshing recalculates after stock changes without writing additional data")
    func refreshesAfterStockChanges() async throws {
        let repository = InMemoryMealRepository(entries: [makeEntry()])
        let model = makeModel(repository)
        await model.load()
        #expect(model.snapshot?.items.first?.quantity == 100)

        try await repository.saveIngredient(Ingredient(name: "Rice", quantity: 100, unit: "g"))
        await model.load()

        #expect(model.snapshot?.items.isEmpty == true)
        #expect(model.snapshot?.plannedMealCount == 1)
        #expect(model.errorMessage == nil)
        let writes = await repository.writeCount
        #expect(writes == 1)
    }

    @Test("Malformed planned ingredients show an error rather than a misleading empty state")
    func invalidIngredientsShowError() async {
        var invalid = makeEntry()
        invalid.meal.ingredients[0].quantity = 0
        let model = makeModel(InMemoryMealRepository(entries: [invalid]))

        await model.load()

        #expect(model.snapshot == nil)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)
    }

    @Test("The existing item-only API agrees with the new snapshot API")
    func preservesItemAPI() async throws {
        let fixedNow = today.addingTimeInterval(12 * 3_600)
        let repository = InMemoryMealRepository(entries: [makeEntry()])
        let useCase = GenerateShoppingListUseCase(repository: repository, calendar: calendar, now: { fixedNow })

        let items = try await useCase.execute()
        let snapshot = try await useCase.executeSnapshot()

        #expect(items == snapshot.items)
        #expect(snapshot.plannedMealCount == 1)
    }

    @Test("A pantry read failure never publishes a partial shopping calculation",
          arguments: [false, true])
    func pantryReadFailure(hasPreviousSnapshot: Bool) async throws {
        var rice = Ingredient(name: "Rice", quantity: 40, unit: "g")
        let base = InMemoryMealRepository(entries: [makeEntry()], ingredients: [rice])
        let repository = ShoppingPantryFailureRepository(base: base)
        let model = makeModel(repository)
        if hasPreviousSnapshot {
            await model.load()
            #expect(model.snapshot?.items.first?.quantity == 60)
        }
        let previous = model.snapshot
        // New demand and stock make both a partial result and an old result detectable.
        try await base.savePlannedMeal(makeEntry())
        rice.quantity = 150
        try await base.saveIngredient(rice)
        await repository.setPantryReadFailure(true)

        await model.refreshAfterDataChange()

        #expect(model.snapshot == previous)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)
        #expect(await repository.successfulPlanReads == (hasPreviousSnapshot ? 2 : 1))
        #expect(await repository.failedPantryReads == 1)
        #expect(await base.writeCount == 2)

        await repository.setPantryReadFailure(false)
        await model.load()
        let result = try #require(model.snapshot)
        #expect(result.plannedMealCount == 2)
        #expect(result.items.count == 1)
        #expect(result.items.first?.quantity == 50)
        #expect(model.errorMessage == nil)
        #expect(!model.isLoading)
        #expect(await base.writeCount == 2)
    }

    private func makeModel(_ repository: any MealPlanningRepository) -> ShoppingListViewModel {
        let fixedNow = today.addingTimeInterval(12 * 3_600)
        return ShoppingListViewModel(repository: repository, calendar: calendar, now: { fixedNow })
    }

    private func makeEntry() -> MealPlanEntry {
        MealPlanEntry(
            meal: Meal(name: "Rice bowl", ingredients: [MealIngredient(name: "Rice", quantity: 100, unit: "g")]),
            scheduledDate: today.addingTimeInterval(18 * 3_600),
            mealType: .dinner
        )
    }
}

/// Fails only the second stage of calculation, after meal plans have loaded successfully.
private actor ShoppingPantryFailureRepository: MealPlanningRepository {
    private let base: InMemoryMealRepository
    private var failPantryRead = false
    private(set) var successfulPlanReads = 0
    private(set) var failedPantryReads = 0

    init(base: InMemoryMealRepository) { self.base = base }

    func setPantryReadFailure(_ failing: Bool) { failPantryRead = failing }

    func fetchAvailableIngredients() async throws -> [Ingredient] {
        if failPantryRead {
            failedPantryReads += 1
            throw RepositoryError.readFailed
        }
        return try await base.fetchAvailableIngredients()
    }

    func fetchMealPlanEntries(from start: Date, to end: Date, includingPrepared includePrepared: Bool) async throws -> [MealPlanEntry] {
        let result = try await base.fetchMealPlanEntries(from: start, to: end, includingPrepared: includePrepared)
        successfulPlanReads += 1
        return result
    }
    func saveMeal(_ meal: Meal) async throws { try await base.saveMeal(meal) }
    func saveIngredient(_ ingredient: Ingredient) async throws { try await base.saveIngredient(ingredient) }
    func saveMealPlanEntry(_ entry: MealPlanEntry) async throws { try await base.saveMealPlanEntry(entry) }
    func savePlannedMeal(_ entry: MealPlanEntry) async throws { try await base.savePlannedMeal(entry) }
    func updateMealPlanEntry(_ entry: MealPlanEntry) async throws { try await base.updateMealPlanEntry(entry) }
    func fetchUpcomingMeals() async throws -> [MealPlanEntry] { try await base.fetchUpcomingMeals() }
    func fetchIngredientsExpiring(before date: Date) async throws -> [Ingredient] {
        try await base.fetchIngredientsExpiring(before: date)
    }
}
