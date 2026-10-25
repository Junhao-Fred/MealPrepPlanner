//  Created by Junhao Huang on 2026/10/23.

import Foundation
import Testing
@testable import MealPrepPlanner

@MainActor
@Suite("Editing, missed meals and bought items")
struct EditingAndFollowUpTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
    }

    private let english = Locale(identifier: "en_AU")

    // MARK: Editing

    @Test("An ingredient draft made for editing saves the same batch with the same values")
    func ingredientDraftRoundTrip() throws {
        let rice = Ingredient(name: "Rice", quantity: Decimal(string: "1.25")!, unit: "kg", expiryDate: today)

        let draft = IngredientEntryDraft(editing: rice, locale: english)

        #expect(draft.quantityText == "1.25")
        #expect(try draft.makeIngredient(locale: english, calendar: calendar) == rice)
    }

    @Test("A meal draft made for editing keeps the plan, recipe and ingredient IDs")
    func mealDraftRoundTrip() throws {
        let entry = MealPlanEntry(
            meal: Meal(name: "Pasta", ingredients: [MealIngredient(name: "Tomato", quantity: Decimal(string: "2.5")!, unit: "piece")]),
            scheduledDate: today.addingTimeInterval(18 * 3_600),
            mealType: .dinner
        )

        let draft = MealEntryDraft(editing: entry, locale: english)

        #expect(draft.ingredients.map(\.quantityText) == ["2.5"])
        #expect(try draft.makeEntry(locale: english) == entry)
    }

    @Test("Saving an edited meal updates it in place instead of adding another")
    func editingMealUpdatesInPlace() async throws {
        let date = today
        let entry = MealPlanEntry(
            meal: Meal(name: "Pasta", ingredients: [MealIngredient(name: "Tomato", quantity: 200, unit: "g")]),
            scheduledDate: date.addingTimeInterval(18 * 3_600),
            mealType: .dinner
        )
        let repository = InMemoryMealRepository(entries: [entry], now: { date })
        let model = MealPlanViewModel(repository: repository, calendar: calendar, now: { date })
        await model.load()

        var draft = MealEntryDraft(editing: entry, locale: english)
        draft.name = "Tomato Pasta"
        draft.ingredients[0].quantityText = "300"
        let saved = await model.save(try draft.makeEntry(locale: english))

        #expect(saved)
        let stored = try await repository.fetchMealPlanEntries(from: date, to: date.addingTimeInterval(86_400), includingPrepared: true)
        #expect(stored.count == 1)
        #expect(stored.first?.id == entry.id)
        #expect(stored.first?.meal.name == "Tomato Pasta")
        #expect(stored.first?.meal.ingredients.first?.quantity == 300)
    }

    // MARK: Missed meals

    @Test("Today lists unprepared meals from the past week, but not prepared or older ones")
    func missedMeals() async throws {
        let date = today.addingTimeInterval(10 * 3_600)
        let yesterday = MealPlanEntry(meal: Meal(name: "Soup", ingredients: []), scheduledDate: today.addingTimeInterval(-6 * 3_600), mealType: .dinner)
        var prepared = MealPlanEntry(meal: Meal(name: "Salad", ingredients: []), scheduledDate: today.addingTimeInterval(-30 * 3_600), mealType: .lunch)
        prepared.isPrepared = true
        let tooOld = MealPlanEntry(meal: Meal(name: "Stew", ingredients: []), scheduledDate: today.addingTimeInterval(-8 * 86_400), mealType: .dinner)
        let repository = InMemoryMealRepository(entries: [yesterday, prepared, tooOld], now: { date })

        let overview = try await LoadTodayOverviewUseCase(repository: repository, calendar: calendar, now: { date }).execute()

        #expect(overview.missedMeals == [yesterday])
    }

    // MARK: Shopping list

    @Test("Marking a shopping item bought adds it to the pantry and clears it from the list")
    func boughtItemMovesToPantry() async throws {
        let date = today
        let entry = MealPlanEntry(
            meal: Meal(name: "Pasta", ingredients: [MealIngredient(name: "Tomato", quantity: 300, unit: "g")]),
            scheduledDate: date.addingTimeInterval(18 * 3_600),
            mealType: .dinner
        )
        let repository = InMemoryMealRepository(entries: [entry], now: { date })
        let model = ShoppingListViewModel(repository: repository, calendar: calendar, now: { date })
        await model.load()
        let item = try #require(model.snapshot?.items.first)

        #expect(await model.addToPantry(item))

        #expect(model.snapshot?.items.isEmpty == true)
        #expect(model.addingItemID == nil)
        let stock = try await repository.fetchAvailableIngredients()
        #expect(stock.map(\.quantity) == [300])
        #expect(stock.map(\.unit) == ["g"])
    }
}
