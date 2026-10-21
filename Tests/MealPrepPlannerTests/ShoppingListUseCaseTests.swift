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

    @Test("Repository read failures propagate instead of appearing as an empty shopping list")
    func propagatesReadFailures() async throws {
        let repository = InMemoryMealRepository(entries: [makeEntry(quantity: 300)])
        await repository.fail(.read, with: .readFailed)

        do {
            _ = try await makeUseCase(repository).execute()
            Issue.record("Expected RepositoryError.readFailed")
        } catch let error as RepositoryError {
            #expect(error == .readFailed)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let writes = await repository.writeCount
        #expect(writes == 0)
    }

    @Test("The window ends at local midnight across a daylight-saving transition")
    func usesCalendarDaysAcrossDaylightSaving() async throws {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))
        let start = try #require(localCalendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        let end = try #require(localCalendar.date(from: DateComponents(year: 2026, month: 10, day: 8)))
        let repository = InMemoryMealRepository(entries: [
            makeEntry(quantity: 100, date: start),
            makeEntry(quantity: 200, date: end.addingTimeInterval(-1)),
            makeEntry(quantity: 1_000, date: end),
            makeEntry(quantity: 2_000, date: end.addingTimeInterval(30 * 60))
        ])
        let fixedNow = start.addingTimeInterval(12 * 3_600)
        let useCase = GenerateShoppingListUseCase(
            repository: repository, calendar: localCalendar, now: { fixedNow }
        )

        let result = try await useCase.execute()

        #expect(result == [item("Rice", quantity: 300, unit: "g")])
    }

    private func makeUseCase(_ repository: InMemoryMealRepository) -> GenerateShoppingListUseCase {
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
