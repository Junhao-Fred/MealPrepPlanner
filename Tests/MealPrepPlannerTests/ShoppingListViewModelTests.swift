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

    private func makeModel(_ repository: InMemoryMealRepository) -> ShoppingListViewModel {
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
