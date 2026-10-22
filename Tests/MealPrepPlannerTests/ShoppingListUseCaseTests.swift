//  Created by Mingchen Liang on 2026/10/19.

import Foundation
import Testing
@testable import MealPrepPlanner

/// T17: shopping quantities reflect combined meal demand minus valid pantry stock.
@Suite("Shopping list aggregation and expiry")
struct ShoppingListUseCaseTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))!
    }

    @Test("T17 shared ingredient demand is summed before stock is deducted: 300 + 250 - 200 = 350")
    func aggregatesDemandBeforeDeductingStock() async throws {
        let repository = InMemoryMealRepository(
            entries: [makeEntry(quantity: 300), makeEntry(quantity: 250)],
            ingredients: [Ingredient(name: "Rice", quantity: 200, unit: "g")]
        )

        let result = try await makeUseCase(repository).execute()

        #expect(result == [item("Rice", quantity: 350, unit: "g")])
    }

    @Test("Matching ignores whitespace and case across recipes and pantry batches")
    func normalizesNamesAndUnitsAndCombinesBatches() async throws {
        let repository = InMemoryMealRepository(
            entries: [makeEntry(ingredients: [
                MealIngredient(name: "  Brown   Rice  ", quantity: 300, unit: " G "),
                MealIngredient(name: "brownrice", quantity: 250, unit: "g")
            ])],
            ingredients: [
                Ingredient(name: "BROWN RICE", quantity: 80, unit: "g"),
                Ingredient(name: "brown\trice", quantity: 120, unit: " G\n")
            ]
        )

        let result = try await makeUseCase(repository).execute()

        #expect(result == [item("Brown Rice", quantity: 350, unit: "G")])
    }

    @Test("The same ingredient in different units stays separate without unit conversion")
    func keepsDifferentUnitsSeparate() async throws {
        let repository = InMemoryMealRepository(
            entries: [makeEntry(ingredients: [
                MealIngredient(name: "Rice", quantity: 300, unit: "g"),
                MealIngredient(name: "Rice", quantity: 2, unit: "kg")
            ])],
            ingredients: [
                Ingredient(name: "Rice", quantity: 100, unit: "g"),
                Ingredient(name: "Rice", quantity: 1, unit: "kg"),
                Ingredient(name: "Rice", quantity: 100, unit: "bag")
            ]
        )

        let result = try await makeUseCase(repository).execute()

        #expect(result == [item("Rice", quantity: 200, unit: "g"),
                           item("Rice", quantity: 1, unit: "kg")])
    }

    @Test("Expired stock is excluded; expiry today, future expiry and undated stock remain valid")
    func respectsExpiryDay() async throws {
        let repository = InMemoryMealRepository(
            entries: [makeEntry(quantity: 500)],
            ingredients: [
                Ingredient(name: "Rice", quantity: 1_000, unit: "g",
                           expiryDate: today.addingTimeInterval(-1)),
                Ingredient(name: "Rice", quantity: 100, unit: "g", expiryDate: today),
                Ingredient(name: "Rice", quantity: 50, unit: "g",
                           expiryDate: calendar.date(byAdding: .day, value: 1, to: today)!),
                Ingredient(name: "Rice", quantity: 75, unit: "g"),
                Ingredient(name: "Rice", quantity: 0, unit: "g")
            ]
        )

        let result = try await makeUseCase(repository).execute()

        #expect(result == [item("Rice", quantity: 275, unit: "g")])
    }

    @Test("Exact or surplus stock produces no shopping item", arguments: [550, 600])
    func omitsCoveredDemand(stock: Int) async throws {
        let repository = InMemoryMealRepository(
            entries: [makeEntry(quantity: 300), makeEntry(quantity: 250)],
            ingredients: [Ingredient(name: "Rice", quantity: Decimal(stock), unit: "g")]
        )

        let result = try await makeUseCase(repository).execute()

        #expect(result.isEmpty)
    }

    @Test("No meal plans produce an empty list even when pantry stock exists")
    func returnsEmptyWithoutPlans() async throws {
        let repository = InMemoryMealRepository(
            ingredients: [Ingredient(name: "Rice", quantity: 200, unit: "g")]
        )

        let result = try await makeUseCase(repository).execute()

        #expect(result.isEmpty)
    }

    @Test("An empty pantry leaves the full recipe demand to buy")
    func returnsFullDemandWithoutStock() async throws {
        let repository = InMemoryMealRepository(entries: [makeEntry(quantity: 300)])

        let result = try await makeUseCase(repository).execute()

        #expect(result == [item("Rice", quantity: 300, unit: "g")])
    }

    @Test("Only unfinished plans in the seven-day half-open interval contribute")
    func filtersPreparedMealsAndDateBoundaries() async throws {
        let end = calendar.date(byAdding: .day, value: 7, to: today)!
        let repository = InMemoryMealRepository(entries: [
            makeEntry(quantity: 1_000, date: today.addingTimeInterval(-1)),
            makeEntry(quantity: 100, date: today),
            makeEntry(quantity: 200, date: end.addingTimeInterval(-1)),
            makeEntry(quantity: 2_000, date: end),
            makeEntry(quantity: 4_000, prepared: true)
        ])

        let result = try await makeUseCase(repository).execute()

        #expect(result == [item("Rice", quantity: 300, unit: "g")])
    }

    @Test("Scheduling the same recipe twice contributes demand twice")
    func countsEachScheduledPreparation() async throws {
        let first = makeEntry(quantity: 100)
        let second = MealPlanEntry(
            meal: first.meal,
            scheduledDate: today.addingTimeInterval(18 * 3_600),
            mealType: .dinner
        )
        let repository = InMemoryMealRepository(
            entries: [first, second],
            ingredients: [Ingredient(name: "Rice", quantity: 50, unit: "g")]
        )

        let result = try await makeUseCase(repository).execute()

        #expect(result == [item("Rice", quantity: 150, unit: "g")])
    }

    @Test("Fractional amounts retain decimal precision")
    func preservesFractionalQuantities() async throws {
        let repository = InMemoryMealRepository(
            entries: [makeEntry(quantity: Decimal(1) / 10),
                      makeEntry(quantity: Decimal(2) / 10)],
            ingredients: [Ingredient(name: "Rice", quantity: Decimal(1) / 10, unit: "g")]
        )

        let result = try await makeUseCase(repository).execute()

        #expect(result == [item("Rice", quantity: Decimal(2) / 10, unit: "g")])
    }

    @Test("Repeated generation returns stable sorted results and leaves plans and stock unchanged")
    func generationIsStableAndReadOnly() async throws {
        let entry = makeEntry(ingredients: [
            MealIngredient(name: "Zucchini", quantity: 2, unit: "piece"),
            MealIngredient(name: "Apple", quantity: 3, unit: "piece"),
            MealIngredient(name: "Apple", quantity: 200, unit: "g")
        ])
        let stock = Ingredient(name: "Apple", quantity: 1, unit: "piece")
        let repository = InMemoryMealRepository(entries: [entry], ingredients: [stock])
        let useCase = makeUseCase(repository)

        let first = try await useCase.execute()
        let second = try await useCase.execute()
        let savedStock = try await repository.fetchAvailableIngredients()
        let savedPlans = try await repository.fetchMealPlanEntries(
            from: today,
            to: calendar.date(byAdding: .day, value: 7, to: today)!,
            includingPrepared: true
        )
        let writes = await repository.writeCount

        #expect(first == [item("Apple", quantity: 200, unit: "g"),
                          item("Apple", quantity: 2, unit: "piece"),
                          item("Zucchini", quantity: 2, unit: "piece")])
        #expect(second == first)
        #expect(savedStock == [stock])
        #expect(savedPlans == [entry])
        #expect(writes == 0)
    }

    enum ReadStage: CaseIterable, Sendable { case plans, pantry }

    @Test("Both shopping APIs preserve repository errors from either read stage",
          arguments: ReadStage.allCases, [RepositoryError.readFailed, .storeUnavailable])
    func propagatesReadFailures(stage: ReadStage, expectedError: RepositoryError) async throws {
        let entry = makeEntry(quantity: 300)
        let stock = Ingredient(name: "Rice", quantity: 100, unit: "g")
        let base = InMemoryMealRepository(entries: [entry], ingredients: [stock])
        let repository = ShoppingReadProbe(base: base, failureStage: stage, failureError: expectedError)
        let useCase = makeUseCase(repository)

        for snapshotAPI in [false, true] {
            do {
                if snapshotAPI {
                    _ = try await useCase.executeSnapshot()
                } else {
                    _ = try await useCase.execute()
                }
                Issue.record("Expected \(expectedError) from \(stage), snapshot API: \(snapshotAPI)")
            } catch let error as RepositoryError {
                #expect(error == expectedError)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
        #expect(await repository.planReads == 2)
        #expect(await repository.pantryReads == (stage == .plans ? 0 : 2))
        #expect(await base.writeCount == 0)

        await repository.clearFailure()
        let recovered = try await useCase.executeSnapshot()
        #expect(recovered.items == [item("Rice", quantity: 200, unit: "g")])
        #expect(recovered.plannedMealCount == 1)
        #expect(await base.writeCount == 0)
        #expect(try await base.fetchAvailableIngredients() == [stock])
        #expect(try await base.fetchMealPlanEntries(from: .distantPast, to: .distantFuture, includingPrepared: true) == [entry])
    }

    @Test("Seven calendar days retain exact boundaries across both daylight-saving transitions",
          arguments: [false, true])
    func usesCalendarDaysAcrossDaylightSaving(fallBack: Bool) async throws {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))
        let month = fallBack ? 4 : 10
        let firstDay = fallBack ? 2 : 1
        let start = try #require(localCalendar.date(from: DateComponents(year: 2026, month: month, day: firstDay)))
        let end = try #require(localCalendar.date(from: DateComponents(year: 2026, month: month, day: firstDay + 7)))
        #expect(end.timeIntervalSince(start) == Double(fallBack ? 169 : 167) * 3_600)
        let repository = InMemoryMealRepository(entries: [
            makeEntry(quantity: 4_000, date: start.addingTimeInterval(-1)),
            makeEntry(quantity: 100, date: start),
            makeEntry(quantity: 200, date: end.addingTimeInterval(-1)),
            makeEntry(quantity: 1_000, date: end),
            makeEntry(quantity: 2_000, date: end.addingTimeInterval(30 * 60)),
            makeEntry(quantity: 8_000, date: start.addingTimeInterval(3_600), prepared: true)
        ])
        let fixedNow = start.addingTimeInterval(12 * 3_600)
        let useCase = GenerateShoppingListUseCase(
            repository: repository, calendar: localCalendar, now: { fixedNow }
        )

        let result = try await useCase.executeSnapshot()

        #expect(result.items == [item("Rice", quantity: 300, unit: "g")])
        #expect(result.startDate == start)
        #expect(result.endDate == end)
        #expect(result.plannedMealCount == 2)
        #expect(await repository.writeCount == 0)
    }

    @Test("Stock remains valid through its local expiry day and expires at the next midnight")
    func expiryRollsOverAtLocalMidnight() async throws {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))
        let start = try #require(localCalendar.date(from: DateComponents(year: 2026, month: 10, day: 4)))
        let nextStart = try #require(localCalendar.date(from: DateComponents(year: 2026, month: 10, day: 5)))
        // This local day has 23 hours; adding a fixed 24 hours would miss the boundary.
        #expect(nextStart.timeIntervalSince(start) == 23 * 3_600)
        let stock = [
            Ingredient(name: "Rice", quantity: 1_000, unit: "g", expiryDate: start.addingTimeInterval(-1)),
            Ingredient(name: "Rice", quantity: 40, unit: "g", expiryDate: start),
            Ingredient(name: "Rice", quantity: 10, unit: "g", expiryDate: nextStart)
        ]
        let repository = InMemoryMealRepository(
            entries: [makeEntry(quantity: 100, date: nextStart.addingTimeInterval(3_600))],
            ingredients: stock
        )
        let beforeMidnight = nextStart.addingTimeInterval(-1)

        let before = try await GenerateShoppingListUseCase(
            repository: repository, calendar: localCalendar, now: { beforeMidnight }
        ).executeSnapshot()
        let after = try await GenerateShoppingListUseCase(
            repository: repository, calendar: localCalendar, now: { nextStart }
        ).executeSnapshot()

        #expect(before.startDate == start)
        #expect(after.startDate == nextStart)
        #expect(before.plannedMealCount == 1)
        #expect(after.plannedMealCount == 1)
        #expect(before.items == [item("Rice", quantity: 50, unit: "g")])
        #expect(after.items == [item("Rice", quantity: 90, unit: "g")])
        let stored = try await repository.fetchAvailableIngredients()
        #expect(stored.count == stock.count)
        #expect(stock.allSatisfy { stored.contains($0) })
        #expect(await repository.writeCount == 0)
    }

    @Test("Excluded plans are not validated or counted and do not require a pantry read")
    func excludedPlansSkipPantryRead() async throws {
        let end = try #require(calendar.date(byAdding: .day, value: 7, to: today))
        // Invalid recipes would fail validation if any excluded plan leaked into demand.
        let base = InMemoryMealRepository(entries: [
            makeEntry(quantity: 0, date: today, prepared: true),
            makeEntry(quantity: 0, date: end.addingTimeInterval(-1), prepared: true),
            makeEntry(quantity: 0, date: today.addingTimeInterval(-1)),
            makeEntry(quantity: 0, date: end)
        ])
        let repository = ShoppingReadProbe(base: base, failureStage: .pantry, failureError: .storeUnavailable)
        let useCase = makeUseCase(repository)

        let snapshot = try await useCase.executeSnapshot()
        let items = try await useCase.execute()

        #expect(snapshot.items.isEmpty)
        #expect(items.isEmpty)
        #expect(snapshot.plannedMealCount == 0)
        #expect(snapshot.startDate == today)
        #expect(snapshot.endDate == end)
        #expect(await repository.planReads == 2)
        #expect(await repository.pantryReads == 0)
        #expect(await base.writeCount == 0)
    }

    private func makeUseCase(_ repository: any MealPlanningRepository) -> GenerateShoppingListUseCase {
        let fixedNow = today.addingTimeInterval(12 * 3_600)
        return GenerateShoppingListUseCase(repository: repository, calendar: calendar, now: { fixedNow })
    }

    private func makeEntry(
        quantity: Decimal = 100,
        date: Date? = nil,
        prepared: Bool = false,
        ingredients: [MealIngredient]? = nil
    ) -> MealPlanEntry {
        MealPlanEntry(
            meal: Meal(name: "Meal", ingredients: ingredients ?? [
                MealIngredient(name: "Rice", quantity: quantity, unit: "g")
            ]),
            scheduledDate: date ?? today.addingTimeInterval(13 * 3_600),
            mealType: .lunch,
            isPrepared: prepared
        )
    }

    private func item(_ name: String, quantity: Decimal, unit: String) -> ShoppingListItem {
        ShoppingListItem(id: .init(name: name, unit: unit), name: name, quantity: quantity, unit: unit)
    }
}

/// Observes the calculation's read stages and injects a failure at exactly one stage.
private actor ShoppingReadProbe: MealPlanningRepository {
    private let base: InMemoryMealRepository
    private var failureStage: ShoppingListUseCaseTests.ReadStage?
    private let failureError: RepositoryError
    private(set) var planReads = 0
    private(set) var pantryReads = 0

    init(base: InMemoryMealRepository, failureStage: ShoppingListUseCaseTests.ReadStage, failureError: RepositoryError) {
        self.base = base
        self.failureStage = failureStage
        self.failureError = failureError
    }

    func clearFailure() { failureStage = nil }

    func fetchMealPlanEntries(from start: Date, to end: Date, includingPrepared includePrepared: Bool) async throws -> [MealPlanEntry] {
        planReads += 1
        if failureStage == .plans { throw failureError }
        return try await base.fetchMealPlanEntries(from: start, to: end, includingPrepared: includePrepared)
    }

    func fetchAvailableIngredients() async throws -> [Ingredient] {
        pantryReads += 1
        if failureStage == .pantry { throw failureError }
        return try await base.fetchAvailableIngredients()
    }

    func saveMeal(_ meal: Meal) async throws { try await base.saveMeal(meal) }
    func saveIngredient(_ ingredient: Ingredient) async throws { try await base.saveIngredient(ingredient) }
    func saveMealPlanEntry(_ entry: MealPlanEntry) async throws { try await base.saveMealPlanEntry(entry) }
    func savePlannedMeal(_ entry: MealPlanEntry) async throws { try await base.savePlannedMeal(entry) }
    func updateMealPlanEntry(_ entry: MealPlanEntry) async throws { try await base.updateMealPlanEntry(entry) }
    func deleteIngredient(id: UUID) async throws { try await base.deleteIngredient(id: id) }
    func deleteMealPlanEntry(id: UUID) async throws { try await base.deleteMealPlanEntry(id: id) }
    func fetchUpcomingMeals() async throws -> [MealPlanEntry] { try await base.fetchUpcomingMeals() }
    func fetchIngredientsExpiring(before date: Date) async throws -> [Ingredient] {
        try await base.fetchIngredientsExpiring(before: date)
    }
}
